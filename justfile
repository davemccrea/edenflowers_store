set shell := ["bash", "-c"]
set dotenv-load

# Override with `PORT=4001 just dev` or `just port=4001 dev`
port := env("PORT", "4000")
imgproxy_port := `echo $(( ${PORT:-4000} + 1 ))`

[private]
default:
    @just --list --unsorted

# Run the development server
[group('development')]
dev: check-typst imgproxy
    PORT={{ port }} IMGPROXY_PREFIX=http://localhost:{{ imgproxy_port }} iex -S mix phx.server

# Start a local imgproxy on PORT+1 (left running), serving images/ read-only and dev uploads from tmp/uploads
[group('development')]
imgproxy:
    #!/usr/bin/env bash
    set -euo pipefail
    docker info >/dev/null 2>&1 || { echo "Docker isn't running: start OrbStack, dev serves photos through a local imgproxy." >&2; exit 1; }
    name=edenflowers-imgproxy-{{ imgproxy_port }}
    [[ -n "$(docker ps -q --filter "name=^$name$")" ]] && exit 0
    # Same image as production. tmp/uploads is mounted over images/uploads, so dev never writes into images/;
    # Docker still needs that folder to exist as the mount point.
    mkdir -p tmp/uploads images/uploads
    docker run -d --rm --name "$name" -p {{ imgproxy_port }}:8080 \
      -e IMGPROXY_KEY -e IMGPROXY_SALT -e IMGPROXY_LOCAL_FILESYSTEM_ROOT=/images \
      -v "$PWD/images:/images:ro" -v "$PWD/tmp/uploads:/images/uploads:ro" \
      darthsim/imgproxy:v3 >/dev/null

# Run the test suite (extra args go to mix test)
[group('development')]
test *args: check-typst
    mix test {{ args }}

# Format all Elixir, JS and CSS files (the pre-commit hook only checks)
[group('development')]
format:
    mix format
    git ls-files '*.js' '*.mjs' '*.cjs' '*.css' ':!:*/vendor/*' | xargs npx --yes prettier@3.3.3 --write

# Forward Stripe webhooks to the local dev server
[group('development')]
stripe-listen:
    stripe listen --events payment_intent.succeeded,payment_intent.payment_failed,payment_intent.canceled,refund.created,refund.updated --forward-to localhost:{{ port }}/webhook/stripe

# Open the Backlog.md issue board in the browser (npm i -g backlog.md)
[group('development')]
issues:
    backlog browser

# Install the Typst CLI used to render receipt PDFs (pinned to the version in production)
[group('setup')]
typst-install:
    ./scripts/install-typst.sh

# Install the Ansible collections used by infra/ (pass --upgrade to update them)
[group('setup')]
[working-directory: 'infra']
infra-install *args:
    ansible-galaxy collection install -r requirements.yml {{ args }}

[private]
check-typst:
    @command -v typst >/dev/null || { echo "typst not found: receipt PDFs (and their tests) need it. Run 'just typst-install'." >&2; exit 1; }

# Drop and migrate the dev and test databases
[group('database')]
db-reset:
    ./scripts/reset-db.sh

# Seed a database (local, or a one-off base seed of an empty production); --stripe creates the Stripe test data behind it
[group('database')]
db-seed target *flags:
    #!/usr/bin/env bash
    set -euo pipefail
    stripe=false
    for flag in {{ flags }}; do
      case "$flag" in
        --stripe) stripe=true ;;
        *) echo "Unknown flag '$flag', use --stripe" >&2; exit 1 ;;
      esac
    done
    # An environment variable doesn't reach the seeds through rpc, so the flag goes into the expression
    flag="Process.put(:seed_stripe, $stripe)"
    case "{{ target }}" in
      local)
        mix run -e "$flag; Code.eval_file(\"priv/repo/seeds.exs\")" ;;
      production)
        if $stripe; then echo "--stripe is for local" >&2; exit 1; fi
        read -r -p "Seed the PRODUCTION database? [y/N] " answer
        [[ "$answer" =~ ^[yY]$ ]] || exit 1
        ssh -T edenflowers-production "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers rpc 'Code.eval_file(Application.app_dir(:edenflowers, \"priv/repo/seeds/production.exs\"))'" ;;
      *)
        echo "Unknown target '{{ target }}', use local or production" >&2; exit 1 ;;
    esac

# Back up the production database to tmp/, named after the release it is running
[group('database')]
db-backup target:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ target }}" in
      production) db=edenflowers_store_prod ;;
      *) echo "Unknown target '{{ target }}', use production" >&2; exit 1 ;;
    esac
    # `bin/edenflowers version` prints "edenflowers 1.7.0"
    version=$(ssh edenflowers-{{ target }} "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers version" | awk '{sub(/\r$/, ""); print "v"$2}') || version=unknown
    mkdir -p tmp
    file="tmp/{{ target }}-$version-$(date +%Y%m%dT%H%M%S).dump"
    ssh edenflowers-{{ target }} "sudo -u postgres pg_dump -Fc $db" > "$file.partial"
    mv "$file.partial" "$file"
    ls -lh "$file"

# Deploy to production
[group('deployment')]
deploy *args:
    ./scripts/deploy.sh {{ args }}

# Roll a server back to a release tag (e.g. v1.6.0), restoring a database backup taken while it ran if one is given
[group('deployment')]
rollback target tag dump="":
    ./scripts/rollback.sh {{ target }} {{ tag }} {{ dump }}

# Follow the latest deploy until it finishes
[group('deployment')]
deploy-watch:
    @gh run watch "$(gh run list --workflow=deploy.yml --limit 1 --json databaseId -q '.[0].databaseId')" --compact --exit-status

# Push images/ to production and pull its uploads back
[group('deployment')]
images-sync:
    ./scripts/sync-images.sh

# Tail the production app logs
[group('server')]
server-logs:
    ssh edenflowers-production 'cd /opt/edenflowers_store && docker compose logs -f --tail=200 app'

# Open a remote IEx console on production
[group('server')]
server-console:
    ssh -t edenflowers-production 'cd /opt/edenflowers_store && docker compose exec app /app/bin/edenflowers remote'

# Dry run: show what provisioning the server would change
[group('infra')]
[working-directory: 'infra']
provision-check:
    ansible-playbook site.yml --check --diff

# Provision the server with infra/ (extra args go to ansible-playbook)
[group('infra')]
[working-directory: 'infra']
provision *args:
    ansible-playbook site.yml {{ args }}

# Edit the Ansible vault
[group('infra')]
[working-directory: 'infra']
vault:
    ansible-vault edit group_vars/all/vault.yml

# Prepare a fresh server as root before its first provision (run once)
[group('infra')]
[working-directory: 'infra']
server-bootstrap:
    ansible-playbook bootstrap.yml

# Lint the Ansible playbooks and roles
[group('infra')]
[working-directory: 'infra']
infra-lint:
    ansible-lint
