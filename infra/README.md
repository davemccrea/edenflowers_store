# Infrastructure

Ansible provisioning for the production server (Ubuntu/Debian). Docker Compose in `/opt/edenflowers_store` runs the app, `imgproxy`, `papra` and `cloudflared`. Postgres runs on the host. Deploys don't go through Ansible, see the main README.

The recipes are in the repo's justfile under `infra`, and run from this folder. Install [Ansible](https://docs.ansible.com/), then `just install-infra` for its collections.

## Vars and vault

- `inventory.ini`: the one host, `production`
- `group_vars/all/vars.yml`: settings, such as `maintenance_mode`
- `group_vars/all/vault.yml`: encrypted secrets, edited with `just edit-vault`. `vault.example.yml` lists every `vault_*` key

The vault password lives in `infra/.vault_pass` (gitignored).

A new env var for the app goes in the vars or vault, then into the app's `environment` in `roles/common/templates/docker-compose.yml.j2`. Run `just provision` before deploying the code that reads it.

## Provision

```bash
just check-provision    # dry run with a diff
just provision          # extra args go to ansible-playbook
```

This updates packages (rebooting if needed), hardens SSH, fail2ban and UFW (only SSH and Tailscale are open, Cloudflare Tunnel brings the traffic), joins Tailscale, sets up Postgres and its 02:00 `pg_dump` (kept 30 days), installs Docker and logs in to ghcr.io, and writes `docker-compose.yml`.

## Off-site database and photo backups

Production's 02:00 job runs `/opt/edenflowers_store/backup.sh` as postgres. It creates a custom-format dump, prunes local dumps older than 30 days, mirrors completed dumps and original uploaded photos to separate Storage Box directories, then pings a Better Stack heartbeat. A failure at any step prevents the heartbeat. Other inventory hosts only dump and prune locally.

The photo source is `/opt/edenflowers_store/images/uploads/`, mounted as the app's `UPLOADS_DIR` (`/app/uploads`). Provisioning creates the directory with mode 0755 and the app writes photos with mode 0644, so postgres can read them without owning them. Verify existing nested directories are traversable and files readable by postgres before the first run. The photo mirror includes all files under uploads, not repository-managed images. It is a live mirror, not an atomic snapshot with the database dump; concurrent uploads/deletions can produce a mismatch.

Before provisioning:

1. Use the main Storage Box account with SSH access enabled; a dedicated sub-account is deferred. The server's transfer key therefore exposes the main account, not just the backup directories, if compromised. Enable independently managed Storage Box snapshots daily, retaining the latest 10 included snapshots. Schedule them after the 02:00 backup normally finishes (for example 04:00, after confirming that allows enough time). This provides roughly 10 days of photo deletion/version recovery, not 30 days. The server's SSH key must not be able to delete those snapshots. Local dump pruning still retains roughly 30 days of dated database dumps in the live mirror; no separate photo pruning job is needed.
2. Create a daily Better Stack heartbeat with enough grace time for the dump and transfer. Configure email alerts to David and test that a missed heartbeat alerts.
3. Add the four `vault_backup_*` settings from `vault.example.yml` using `just edit-vault`. Verify the SSH host key independently with Hetzner before recording it; do not blindly trust `ssh-keyscan` output.
4. If an older job already stores dumps directly in `edenflowers/`, pause its cron before provisioning or creating child directories. Copy those dumps into `edenflowers/database/`, verify the copies (including `pg_restore --list` on a downloaded dump), and keep the old dumps until the new layout and restore have been verified. Never run the old root-level `rsync --delete` after creating child directories: it would delete them.
5. Provision. The playbook prints postgres's dedicated public key. Authorize that key on the main account using `cat key.pub | ssh -p23 <account>@<host> install-ssh-key` from your machine. The cron may fail until authorization is complete; existing local backups still run.
6. Ensure `edenflowers/database/` and `edenflowers/photos/` exist on the box. Resume the cron only once the new script is installed and the destination layout is ready.
7. Run `sudo -u postgres /opt/edenflowers_store/backup.sh` on production. Confirm the latest dump is in `edenflowers/database/`, uploaded photos are in `edenflowers/photos/`, and Better Stack received the heartbeat. Each mirror uses `--delete` only within its own directory: do not put unrelated files there, and never target their shared parent.

Restore verification: download a dump with `rsync -a -e 'ssh -p23' <account>@<host>:edenflowers/database/<file>.dump ./`, inspect it with `pg_restore --list`, then restore into an isolated disposable database and check its contents. Download photos into an isolated local directory with `rsync -a -e 'ssh -p23' <account>@<host>:edenflowers/photos/ ./restored-photos/`; compare file hashes with originals and open representative images. Never test restores against production. Also verify recovery of a dump and a deleted photo from a Storage Box snapshot, not just the live mirrors. Use a disposable test photo for the deletion check, not a shop photo.

The heartbeat URL is secret. The generated script is readable only by root and postgres, and Ansible suppresses its rendered diff. This is SSH transport encryption, not client-side encryption at rest.

Local checks (use the Python environment that has Ansible/Jinja installed; ShellCheck must be on PATH):

```bash
python -m unittest discover -s infra/tests -v
ansible-lint infra/roles/common/tasks/backups.yml
# From infra/:
ansible-playbook site.yml --syntax-check
```

## Weblate

Separate Compose stack and Cloudflare Tunnel at `/opt/weblate`; app deploys leave
it alone. No host ports are published.

- Vault: add `vault_weblate_db_password` (`openssl rand -hex 32`),
  `vault_brevo_smtp_user` and `vault_brevo_smtp_password` (Brevo **SMTP** credentials,
  not the API key).
- Provision: `just backup`, confirm the dump in `tmp/`, then
  `just provision --tags weblate`. Check the bridge subnet in `vars.yml` is unused.
- Create a **dedicated** Cloudflare Tunnel; save its token as
  `vault_weblate_cloudflare_tunnel_token`. Route `weblate.edenflowers.fi` to
  `http://weblate:8080` in that tunnel. Remove any old route from the shop's tunnel.
- Initial admin password: `sudo docker compose --project-directory /opt/weblate logs weblate`
  on the server. Change it after sign-in; test email before inviting reviewers.
- Registration is closed. Configure a **private** project, Git access and reviewer
  permissions in Weblate; use a translation branch, not `main`.
- Backups: 03:00, 30-day retention in `/opt/weblate/backups`; briefly stops Weblate,
  not the shop. **Local only; off-server copies still needed.** Restore both the
  database dump and data archive. Valkey queues are excluded.
- Upgrades: back up first, change the pinned image in `vars.yml`, provision.
  PostgreSQL major upgrades need dump/restore. Never `docker compose down -v`.

## New server

`just bootstrap` runs once, as root, on a fresh server. It creates the user from `vars.yml` with passwordless sudo, authorizes `~/.ssh/id_rsa.pub` and `github_actions_public_key`, and disables root SSH login. Then provision it, deploy, and seed the empty database with the rows the admin can't create:

```bash
ssh -T edenflowers-production "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers rpc 'Code.eval_file(Application.app_dir(:edenflowers, \"priv/repo/seeds/production.exs\"))'"
```

The deploy workflow SSHes in with the private half of `github_actions_public_key`, stored as `DEPLOY_SSH_KEY` next to `DEPLOY_HOST` and `DEPLOY_USER` in the `production` GitHub environment.

## Monitoring

Better Stack's uptime monitor checks https://edenflowers.fi/health every 3 minutes and emails David when it fails. The route answers 200 only when the app can reach the database. Deploys pause the monitor while the app restarts.
