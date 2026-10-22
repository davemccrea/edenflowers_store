set shell := ["bash", "-c"]
set dotenv-load

# Override with `PORT=4001 just dev` or `just port=4001 dev`
port := env("PORT", "4000")
imgproxy_port := shell('echo $(( $1 + 1 ))', port)

[private]
default:
    @just --list --unsorted

# Run the development server
[group('development')]
dev: check-typst imgproxy
    PORT={{ port }} IMGPROXY_PREFIX=http://localhost:{{ imgproxy_port }} iex -S mix phx.server

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

# Drop and migrate the local dev and test databases
[group('development')]
db-reset:
    mix ecto.drop
    mix ash.setup
    MIX_ENV=test mix ecto.drop
    MIX_ENV=test mix ash.setup

# Seed the local database; --stripe creates the Stripe test data behind it
[group('development')]
db-seed *flags:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ flags }}" in
      "") stripe=false ;;
      --stripe) stripe=true ;;
      *) echo "Unknown flag '{{ flags }}', use --stripe" >&2; exit 1 ;;
    esac
    mix run -e "Process.put(:seed_stripe, $stripe); Code.eval_file(\"priv/repo/seeds.exs\")"

# Start a local imgproxy on PORT+1 (left running), serving images/ read-only and dev uploads from tmp/uploads
[private]
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

[private]
check-typst:
    @command -v typst >/dev/null || { echo "typst not found: receipt PDFs (and their tests) need it. Run 'just typst-install'." >&2; exit 1; }

# Install the Typst CLI used to render receipt PDFs (pinned to the version in production)
[group('setup')]
typst-install:
    ./scripts/install-typst.sh

# Install the Ansible collections used by infra/ (pass --upgrade to update them)
[group('setup')]
[working-directory: 'infra']
infra-install *args:
    ansible-galaxy collection install -r requirements.yml {{ args }}

# Tag a release from main and deploy it (prompts for the version if not given)
[group('production')]
deploy version="":
    ./scripts/deploy.sh {{ version }}

# Follow the latest deploy until it finishes
[group('production')]
deploy-watch:
    @gh run watch "$(gh run list --workflow=deploy.yml --limit 1 --json databaseId -q '.[0].databaseId')" --compact --exit-status

# Run an old release (e.g. v1.6.0), restoring a database backup taken while it ran if one is given
[group('production')]
rollback tag dump="":
    ./scripts/rollback.sh {{ tag }} {{ dump }}

# Back up the production database to tmp/, named after the release it is running
[group('production')]
backup:
    #!/usr/bin/env bash
    set -euo pipefail
    # `bin/edenflowers version` prints "edenflowers 1.7.0"
    version=$(ssh edenflowers-production "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers version" | awk '{print "v"$2}') || version=unknown
    mkdir -p tmp
    file="tmp/production-$version-$(date +%Y%m%dT%H%M%S).dump"
    ssh edenflowers-production "sudo -u postgres pg_dump -Fc edenflowers_store_prod" > "$file.partial"
    mv "$file.partial" "$file"
    ls -lh "$file"

# Push images/ to production and pull its uploads back
[group('production')]
images-sync:
    ./scripts/sync-images.sh

# Tail the production app logs
[group('production')]
server-logs:
    ssh edenflowers-production 'cd /opt/edenflowers_store && docker compose logs -f --tail=200 app'

# Open a remote IEx console on production
[group('production')]
server-console:
    ssh -t edenflowers-production 'cd /opt/edenflowers_store && docker compose exec app /app/bin/edenflowers remote'

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

# Lint the Ansible playbooks and roles
[group('infra')]
[working-directory: 'infra']
infra-lint:
    ansible-lint
