set shell := ["bash", "-c"]
set dotenv-load

# Override with `PORT=4001 just dev` or `just port=4001 dev`
port := env("PORT", "4000")

[private]
default:
    @just --list --unsorted

# Run the development server
[group('development')]
dev: check-typst
    PORT={{ port }} iex -S mix phx.server

# Run the test suite (extra args go to mix test)
[group('development')]
test *args: check-typst
    mix test {{ args }}

# Forward Stripe webhooks to the local dev server
[group('development')]
stripe-listen:
    stripe listen --events payment_intent.succeeded,payment_intent.payment_failed,payment_intent.canceled,refund.created,refund.updated --forward-to localhost:{{ port }}/webhook/stripe

# Install the Typst CLI used to render receipt PDFs (pinned to the version in production)
[group('setup')]
typst-install:
    ./scripts/install-typst.sh

[private]
check-typst:
    @command -v typst >/dev/null || { echo "typst not found: receipt PDFs (and their tests) need it. Run 'just typst-install'." >&2; exit 1; }

# Drop and set up the dev and test databases (run `just db-seed local` afterwards for data)
[group('database')]
db-reset:
    ./scripts/reset-db.sh

# Seed a database (local or staging, never production)
[group('database')]
db-seed target:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ target }}" in
      local)
        mix run priv/repo/seeds.exs ;;
      staging)
        ssh -T edenflowers-staging "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers rpc 'Code.eval_file(Application.app_dir(:edenflowers, \"priv/repo/seeds.exs\"))'" ;;
      *)
        echo "Unknown target '{{ target }}', use local or staging" >&2; exit 1 ;;
    esac

# Seed an empty production database with admins, tax rates, delivery options and categories (fails if already seeded)
[confirm("Seed the PRODUCTION database? [y/N]")]
[group('database')]
db-seed-production:
    ssh -T edenflowers-production "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers rpc 'Code.eval_file(Application.app_dir(:edenflowers, \"priv/repo/seeds/production.exs\"))'"

# Back up the production database to tmp/
[group('database')]
db-backup-production:
    @mkdir -p tmp
    ssh edenflowers-production 'sudo -u postgres pg_dump -Fc edenflowers_store_prod' > tmp/production-$(date +%F).dump
    @ls -lh tmp/production-$(date +%F).dump

# Wipe the staging database, leaving an empty schema for the next deploy to migrate
[confirm("Wipe the STAGING database? [y/N]")]
[group('database')]
db-wipe-staging:
    #!/usr/bin/env bash
    set -euo pipefail
    ssh -T edenflowers-staging bash -s <<'EOF'
    set -euo pipefail
    cd /opt/edenflowers_store
    db=edenflowers_store_staging
    # The app role is the one granted on the database by provisioning; schema_migrations may already be gone
    app_role=$(sudo -u postgres psql -tA -d "$db" -c "select distinct grantee::regrole from pg_database, aclexplode(datacl) where datname = current_database() and grantee <> datdba and grantee <> 0")
    if [ -z "$app_role" ]; then echo "Could not find the app role for $db" >&2; exit 1; fi
    docker compose stop app
    sudo -u postgres psql -v ON_ERROR_STOP=1 -d "$db" \
      -c "drop schema public cascade" \
      -c "create schema public" \
      -c "grant all on schema public to $app_role" \
      -c "create extension citext"
    EOF

# Deploy to staging or production (asks if no target is given)
[group('deployment')]
deploy *args:
    ./scripts/deploy.sh {{ args }}

# Show recent deploys and follow the latest one until it finishes
[group('deployment')]
deploy-watch:
    @gh run list --workflow=deploy.yml --limit 5
    @gh run watch "$(gh run list --workflow=deploy.yml --limit 1 --json databaseId -q '.[0].databaseId')" --compact --exit-status

# Sync images/ to servers (staging, production, or both by default)
[group('deployment')]
images-sync target="all":
    ./scripts/sync-images.sh {{ target }}

# Tail app logs on a server (staging or production)
[group('server')]
server-logs target:
    ssh edenflowers-{{ target }} 'cd /opt/edenflowers_store && docker compose logs -f --tail=200 app'

# Open a remote IEx console on a server (staging or production)
[group('server')]
server-console target:
    ssh -t edenflowers-{{ target }} 'cd /opt/edenflowers_store && docker compose exec app /app/bin/edenflowers remote'

# Backwards-compatible aliases for the previous command names. Keep these out of `just --list`.
[private]
alias install-typst := typst-install
[private]
alias reset-local-db := db-reset
[private]
alias seed := db-seed
[private]
alias seed-production := db-seed-production
[private]
alias dump-production-db := db-backup-production
[private]
alias reset-staging-db := db-wipe-staging
[private]
alias deploy-status := deploy-watch
[private]
alias sync-images := images-sync
[private]
alias logs := server-logs
[private]
alias console := server-console
