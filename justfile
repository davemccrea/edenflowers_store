[private]
default:
    @just --list --unsorted

# Start the dev server with .env loaded
[group('local')]
dev:
    source .env && iex -S mix phx.server

# Run the test suite with .env loaded (extra args go to mix test)
[group('local')]
test *args:
    source .env && mix test {{args}}

# Forward Stripe webhooks to the local dev server
[group('local')]
stripe-listen:
    stripe listen --events payment_intent.succeeded,payment_intent.payment_failed,payment_intent.canceled --forward-to localhost:4000/webhook/stripe

# Drop and set up the dev and test databases (run `just seed local` afterwards for data)
[group('local')]
reset-local-db:
    ./scripts/reset-db.sh

# Seed a database (local or staging, never production)
[group('local')]
[group('server')]
seed target:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{target}}" in
      local)
        source .env && mix run priv/repo/seeds.exs ;;
      staging)
        ssh -T edenflowers-staging "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers rpc 'Code.eval_file(Application.app_dir(:edenflowers, \"priv/repo/seeds.exs\"))'" ;;
      *)
        echo "Unknown target '{{target}}', use local or staging" >&2; exit 1 ;;
    esac

# Deploy to staging or production (asks if no target is given)
[group('deploy')]
deploy *args:
    ./scripts/deploy.sh {{args}}

# Show recent deploys and follow the latest one until it finishes
[group('deploy')]
deploy-status:
    @gh run list --workflow=deploy.yml --limit 5
    @gh run watch "$(gh run list --workflow=deploy.yml --limit 1 --json databaseId -q '.[0].databaseId')" --compact --exit-status

# Sync images/ to servers (staging, production, or both by default)
[group('deploy')]
sync-images target="all":
    ./scripts/sync-images.sh {{target}}

# Tail app logs on a server (staging or production)
[group('server')]
logs target:
    ssh edenflowers-{{target}} 'cd /opt/edenflowers_store && docker compose logs -f --tail=200 app'

# Open a remote IEx console on a server (staging or production)
[group('server')]
console target:
    ssh -t edenflowers-{{target}} 'cd /opt/edenflowers_store && docker compose exec app /app/bin/edenflowers remote'

# Dump the production database to tmp/
[group('server')]
dump-production-db:
    @mkdir -p tmp
    ssh edenflowers-production 'sudo -u postgres pg_dump -Fc edenflowers_store_prod' > tmp/production-$(date +%F).dump
    @ls -lh tmp/production-$(date +%F).dump

# Wipe the staging database, leaving an empty schema for the next deploy to migrate (hardcoded to staging, never production)
[group('server')]
[confirm("Wipe the STAGING database? [y/N]")]
reset-staging-db:
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
