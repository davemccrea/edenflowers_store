# Infrastructure

Ansible provisioning for the production server (Ubuntu/Debian):

- The app, `imgproxy`, `papra` and `cloudflared` run under Docker Compose in `/opt/edenflowers_store`
- Postgres runs directly on the host, managed by Ansible
- Ansible handles server setup only. Deploys run through GitHub Actions (`.github/workflows/deploy.yml`), see the main README

The `just` recipes in the repo's justfile run from this folder, under the `infra` group. Install [Ansible](https://docs.ansible.com/), then:

```bash
just infra-install             # Ansible collections (or: just infra-install --upgrade)
```

## Hosts and vars

Hosts are in `inventory.ini` (`production`). Every recipe that touches a server takes that host name.

Shared settings live in `group_vars/all/vars.yml`. Per-host overrides (`project_url`, `tailscale_hostname`, `papra_base_url`, `imgproxy_prefix`, `maintenance_mode`) live in `host_vars/<host>/vars.yml`.

## Vault

Secrets shared by all hosts live in `group_vars/all/vault.yml`. Each host has its own `host_vars/<host>/vault.yml` for the rest, and can override a shared secret there. `vault.example.yml` lists every `vault_*` variable with placeholder values and generation hints; its header says which are shared.

```bash
just vault                     # group_vars/all/vault.yml
just vault production          # host_vars/production/vault.yml
```

The vault password goes in `infra/.vault_pass` (gitignored), so you aren't asked for it on every run:

```bash
echo 'my_vault_password' > infra/.vault_pass
```

A new env var for the app means adding it to the vars or vault, and passing it to the container in `roles/common/templates/docker-compose.yml.j2`. Then `just provision production` before deploying the code that reads it.

The Cloudflare Tunnel token comes from the Cloudflare Zero Trust dashboard when you create a tunnel. Point the tunnel's public hostname at `http://localhost:<app_port>`.

## Bootstrap (once, on a fresh server)

Creates the user defined in `group_vars/all/vars.yml`, authorizes `~/.ssh/id_rsa.pub` and the GitHub Actions key, and disables root SSH login. Run once as root:

```bash
just bootstrap production
```

## Provision

```bash
just provision-check production    # dry run, shows a diff of what would change
just provision production          # extra args go to ansible-playbook, e.g. --tags docker
```

This playbook:

- Updates packages and reboots if required
- Applies security hardening (UFW, fail2ban, SSH)
- Installs and connects Tailscale
- Installs and configures Postgres, creates the database and user
- Installs Docker and logs in to ghcr.io
- Places `docker-compose.yml` at `/opt/edenflowers_store/docker-compose.yml`
- Schedules daily Postgres backups at 02:00, kept for 30 days

> [!NOTE]
> UFW only opens port 22 (SSH) and the Tailscale interface. Ports 80/443 are not needed, all traffic arrives via the Cloudflare Tunnel.

## GitHub Actions deploy key

The deploy workflow needs a GitHub environment named `production` with `DEPLOY_HOST`, `DEPLOY_USER` and `DEPLOY_SSH_KEY` secrets. Generate a dedicated key pair:

```bash
ssh-keygen -t ed25519 -C "github-actions" -f ~/.ssh/github_actions -N ""
```

Put the public key in `group_vars/all/vars.yml` as `github_actions_public_key`; `just bootstrap` adds it to `authorized_keys`. Add the private key as the `DEPLOY_SSH_KEY` secret.

## Linting

```bash
just infra-lint
```

## Connect with Livebook

Start Livebook locally and use "Attached Node" to connect to the node on the server. The node name is the Tailscale hostname plus the tailnet name, e.g. `edenflowers@my-server.tail1234.ts.net`.
