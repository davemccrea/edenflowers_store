# List available commands
default:
    @just --list --unsorted

# Start the dev server with .env loaded
dev:
    source .env && iex -S mix phx.server

# Forward Stripe webhooks to the local dev server
stripe:
    stripe listen --forward-to localhost:4000/webhook/stripe

# Drop, set up and seed the dev and test databases
reset-db:
    ./scripts/reset-db.sh

# Deploy to staging or production (asks if no target is given)
deploy *args:
    ./scripts/deploy.sh {{args}}

# Show recent deploys and follow the latest one until it finishes
status:
    @gh run list --workflow=deploy.yml --limit 5
    @gh run watch "$(gh run list --workflow=deploy.yml --limit 1 --json databaseId -q '.[0].databaseId')" --compact --exit-status

# Sync images/ to servers (staging, production, or both by default)
images target="all":
    ./scripts/sync-images.sh {{target}}

# Tail app logs on a server (staging or production)
logs target:
    ssh edenflowers-{{target}} 'cd /opt/edenflowers_store && docker compose logs -f --tail=200 app'

# Open a remote IEx console on a server (staging or production)
console target:
    ssh -t edenflowers-{{target}} 'cd /opt/edenflowers_store && docker compose exec app /app/bin/edenflowers remote'
