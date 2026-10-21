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

# Format all Elixir, JS and CSS files (the pre-commit hook only checks)
[group('development')]
format:
    mix format
    git ls-files '*.js' '*.mjs' '*.cjs' '*.css' ':!:*/vendor/*' | xargs npx --yes prettier@3.3.3 --write

# Export customer email wording scenarios in English, Swedish and Finnish
[group('development')]
email-previews:
    mix run --no-start scripts/email-previews.exs

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

[private]
check-typst:
    @command -v typst >/dev/null || { echo "typst not found: receipt PDFs (and their tests) need it. Run 'just typst-install'." >&2; exit 1; }

# Drop and migrate a database (local: dev and test; staging: also reseeds it with Stripe test data)
[group('database')]
db-reset target:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ target }}" in
      local)
        ./scripts/reset-db.sh ;;
      staging)
        echo "Stripe has no API to wipe test data. First use \"Delete all test data\" in the staging Stripe Dashboard,"
        echo "or recreate the sandbox and update staging's keys and webhook secret."
        read -r -p "Wipe and reseed the STAGING database? [y/N] " answer
        [[ "$answer" =~ ^[yY]$ ]] || exit 1
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
    # Without </dev/null, run reads the rest of this script from stdin and the app never starts
    docker compose run --rm -T app /app/bin/migrate </dev/null
    docker compose up -d app
    for _ in $(seq 60); do
      docker compose exec -T app /app/bin/edenflowers rpc ':ok' >/dev/null 2>&1 && exit 0
      sleep 2
    done
    echo "The app didn't come up within 2 minutes" >&2; exit 1
    EOF
        just db-seed staging --stripe ;;
      *)
        echo "Unknown target '{{ target }}', use local or staging" >&2; exit 1 ;;
    esac

# Seed a database (local, staging, or a one-off base seed of an empty production); --stripe creates the Stripe test data behind it
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
      staging)
        ssh -T edenflowers-staging "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers rpc '$flag; Code.eval_file(Application.app_dir(:edenflowers, \"priv/repo/seeds.exs\"))'" ;;
      production)
        if $stripe; then echo "--stripe is for local and staging" >&2; exit 1; fi
        read -r -p "Seed the PRODUCTION database? [y/N] " answer
        [[ "$answer" =~ ^[yY]$ ]] || exit 1
        ssh -T edenflowers-production "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers rpc 'Code.eval_file(Application.app_dir(:edenflowers, \"priv/repo/seeds/production.exs\"))'" ;;
      *)
        echo "Unknown target '{{ target }}', use local, staging or production" >&2; exit 1 ;;
    esac

# Back up a server's database (staging or production) to tmp/, named after the release it is running
[group('database')]
db-backup target:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ target }}" in
      staging) db=edenflowers_store_staging ;;
      production) db=edenflowers_store_prod ;;
      *) echo "Unknown target '{{ target }}', use staging or production" >&2; exit 1 ;;
    esac
    # `bin/edenflowers version` prints "edenflowers 1.7.0"
    version=$(ssh edenflowers-{{ target }} "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers version" | awk '{print "v"$2}') || version=unknown
    mkdir -p tmp
    file="tmp/{{ target }}-$version-$(date +%Y%m%dT%H%M%S).dump"
    ssh edenflowers-{{ target }} "sudo -u postgres pg_dump -Fc $db" > "$file.partial"
    mv "$file.partial" "$file"
    ls -lh "$file"

# Roll a server back to a release tag (e.g. v1.6.0) and restore a database backup taken while it ran
[group('database')]
db-rollback target tag dump:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{ target }}" in
      staging) db=edenflowers_store_staging ;;
      production) db=edenflowers_store_prod ;;
      *) echo "Unknown target '{{ target }}', use staging or production" >&2; exit 1 ;;
    esac
    [[ -s "{{ dump }}" ]] || { echo "No dump at {{ dump }}" >&2; exit 1; }
    [[ "{{ dump }}" == *"{{ tag }}"* ]] || echo "Warning: {{ dump }} was not taken while {{ tag }} was running."
    echo "This replaces the {{ target }} database with {{ dump }} and runs {{ tag }}."
    echo "Anything written since that backup (orders, payments) is lost; check Stripe for payments to reconcile."
    read -r -p "Roll back {{ target }}? [y/N] " answer
    [[ "$answer" =~ ^[yY]$ ]] || exit 1
    # The rollback itself must be undoable
    just db-backup {{ target }}
    ssh -T edenflowers-{{ target }} "sudo -u postgres tee /tmp/rollback.dump >/dev/null" < "{{ dump }}"
    ssh -T edenflowers-{{ target }} bash -s <<EOF
    set -euo pipefail
    cd /opt/edenflowers_store
    # Compose runs a moving tag (latest or staging), so point it at the old release's image
    image=\$(docker compose config --images app)
    docker pull "\${image%:*}:{{ trim_start_match(tag, "v") }}"
    docker tag "\${image%:*}:{{ trim_start_match(tag, "v") }}" "\$image"
    docker compose stop app
    sudo -u postgres dropdb --force $db
    # --create restores the database's owner and grants along with it
    sudo -u postgres pg_restore --create --exit-on-error -d postgres /tmp/rollback.dump
    sudo rm /tmp/rollback.dump
    docker compose up -d app
    for _ in \$(seq 60); do
      docker compose exec -T app /app/bin/edenflowers rpc ':ok' >/dev/null 2>&1 && exit 0
      sleep 2
    done
    echo "The app didn't come up within 2 minutes" >&2; exit 1
    EOF
    echo "{{ target }} is on {{ tag }}. The next deploy pulls the moving tag again."

# Deploy to staging or production (asks if no target is given)
[group('deployment')]
deploy *args:
    ./scripts/deploy.sh {{ args }}

# Follow the latest deploy until it finishes
[group('deployment')]
deploy-watch:
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

