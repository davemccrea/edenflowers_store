# List available commands
default:
    @just --list

# Start the dev server with .env loaded
dev:
    source .env && iex -S mix phx.server

# Drop, set up and seed the dev and test databases
reset-db:
    ./scripts/reset-db.sh

# Deploy to staging or production (asks if no target is given)
deploy *args:
    ./scripts/deploy.sh {{args}}

# Sync images/ to servers (staging, production, or both by default)
images target="all":
    ./scripts/sync-images.sh {{target}}

# Tail app logs on a server (staging or production)
logs target:
    ssh edenflowers-{{target}} 'cd /opt/edenflowers_store && docker compose logs -f --tail=200 app'

# Open a remote IEx console on a server (staging or production)
console target:
    ssh -t edenflowers-{{target}} 'cd /opt/edenflowers_store && docker compose exec app /app/bin/edenflowers remote'
