# Infrastructure

Ansible provisioning for the production server (Ubuntu/Debian). Docker Compose in `/opt/edenflowers_store` runs the app, `imgproxy`, `papra` and `cloudflared`. Postgres runs on the host. Deploys don't go through Ansible, see the main README.

The recipes are in the repo's justfile under `infra`, and run from this folder. Install [Ansible](https://docs.ansible.com/), then `just infra-install` for its collections.

## Vars and vault

- `inventory.ini`: hosts (`production`)
- `group_vars/all/vars.yml`: shared settings
- `host_vars/production/vars.yml`: per-host settings, such as `maintenance_mode`
- `group_vars/all/vault.yml`, `host_vars/production/vault.yml`: encrypted secrets, shared and per-host. `vault.example.yml` lists every `vault_*` key

```bash
just vault                     # edit the shared vault
just vault production          # edit the production vault
```

The vault password lives in `infra/.vault_pass` (gitignored).

A new env var for the app goes in the vars or vault, then into the app's `environment` in `roles/common/templates/docker-compose.yml.j2`. Run `just provision production` before deploying the code that reads it.

## Provision

```bash
just provision-check production    # dry run with a diff
just provision production          # extra args go to ansible-playbook, e.g. --tags docker
```

This updates packages (rebooting if needed), hardens SSH, fail2ban and UFW (only SSH and Tailscale are open, Cloudflare Tunnel brings the traffic), joins Tailscale, sets up Postgres and its 02:00 `pg_dump` (kept 30 days), installs Docker and logs in to ghcr.io, and writes `docker-compose.yml`.

## New server

`just server-bootstrap production` runs once, as root, on a fresh server. It creates the user from `vars.yml` with passwordless sudo, authorizes `~/.ssh/id_rsa.pub` and `github_actions_public_key`, and disables root SSH login. Then provision it.

The deploy workflow SSHes in with the private half of `github_actions_public_key`, stored as `DEPLOY_SSH_KEY` next to `DEPLOY_HOST` and `DEPLOY_USER` in the `production` GitHub environment.
