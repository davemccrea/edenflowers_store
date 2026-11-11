set shell := ["bash", "-c"]
set dotenv-load

# Override with `PORT=4001 just dev` or `just port=4001 dev`
port := env("PORT", "4000")
imgproxy_port := shell('echo $(( $1 + 1 ))', port)

[private]
default:
    @just --list --unsorted

# Install the Typst CLI used to render receipt PDFs (pinned to the version in production)
[group('development')]
install-typst:
    ./scripts/install-typst.sh

# Run the development server
[group('development')]
dev: check-typst start-imgproxy
    # Start IEx only with a terminal attached; it exits on EOF when run in the background.
    # Use the Tailscale IP for photo URLs so other devices can load them, falling back to localhost.
    PORT={{ port }} IMGPROXY_PREFIX=http://$(tailscale ip -4 2>/dev/null || echo localhost):{{ imgproxy_port }} $([ -t 0 ] && echo iex -S) mix phx.server

# Run both suites with no args; extra args run only the focused Elixir suite
[group('development')]
test *args: check-typst
    {{ if args == "" { "just test-js" } else { "true" } }}
    mix test {{ args }}

# Run the JavaScript contracts without Mix or database setup
[group('development')]
test-js:
    node --test --test-reporter=dot test/js/*_test.mjs

# Write tmp/emails.md: Claude's map of when each email is sent, then every email in every language
[group('development')]
map-emails:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p tmp
    mix compile --no-all-warnings > /dev/null
    previews=$(mix print_emails)
    map=$(claude -p --allowedTools "Read,Grep,Glob" < docs/agents/email-map.md) || { echo "$map" >&2; exit 1; }
    printf '%s\n\n%s\n' "$map" "$previews" > tmp/emails.md
    echo "Wrote tmp/emails.md"

# Format all Elixir, JS and CSS files (the pre-commit hook only checks)
[group('development')]
format:
    mix format
    git ls-files '*.js' '*.mjs' '*.cjs' '*.css' ':!:*/vendor/*' | xargs npx --yes prettier@3.3.3 --write

# Forward Stripe webhooks to the local dev server
[group('development')]
forward-stripe:
    stripe listen --events payment_intent.succeeded,payment_intent.payment_failed,payment_intent.canceled,refund.created,refund.updated --forward-to localhost:{{ port }}/webhook/stripe

# Open the Backlog.md issue board in the browser (npm i -g backlog.md)
[group('development')]
open-issues:
    backlog browser

# Drop and migrate the local dev and test databases
[group('development')]
reset-db:
    mix ecto.drop
    mix ash.setup
    MIX_ENV=test mix ecto.drop
    MIX_ENV=test mix ash.setup

# Seed the local database; --stripe creates the Stripe test data behind it
[group('development')]
seed-db *flags:
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
start-imgproxy:
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
    @command -v typst >/dev/null || { echo "typst not found: receipt PDFs (and their tests) need it. Run 'just install-typst'." >&2; exit 1; }

# Install the Ansible collections used by infra/ (pass --upgrade to update them)
[group('infra')]
[working-directory: 'infra']
install-infra *args:
    ansible-galaxy collection install -r requirements.yml {{ args }}

# Edit the Ansible vault
[group('infra')]
[working-directory: 'infra']
edit-vault:
    EDITOR=nvim ansible-vault edit group_vars/all/vault.yml

# Prepare a fresh server as root before its first provision (run once)
[group('infra')]
[working-directory: 'infra']
bootstrap:
    ansible-playbook bootstrap.yml

# Dry run: show what provisioning the server would change
[group('infra')]
[working-directory: 'infra']
check-provision:
    ansible-playbook site.yml --check --diff

# Provision the server with infra/ (extra args go to ansible-playbook)
[group('infra')]
[working-directory: 'infra']
provision *args:
    ansible-playbook site.yml {{ args }}

# Lint the Ansible playbooks and roles
[group('infra')]
[working-directory: 'infra']
lint-infra:
    ansible-lint

# Tag a release from main and deploy it: `just deploy [patch|minor|major] [--yes]` (--yes defaults to patch and skips the release notes edit)
[group('production')]
deploy *args:
    ./scripts/deploy.sh {{ args }}

# Follow the latest deploy until it finishes
[group('production')]
watch-deploy:
    @gh run watch "$(gh run list --workflow=deploy.yml --limit 1 --json databaseId -q '.[0].databaseId')" --compact --exit-status

# Run an old release (e.g. v1.6.0), restoring a database backup taken while it ran if one is given
[group('production')]
rollback tag dump="":
    ./scripts/rollback.sh {{ tag }} {{ dump }}

# Restore a dump into a throwaway local Postgres the way `just rollback` would, and print row counts
[group('production')]
check-restore dump:
    ./scripts/check-restore.sh {{ dump }}

# Back up the production database to tmp/, named after the release it is running
[group('production')]
backup:
    #!/usr/bin/env bash
    set -euo pipefail
    # `bin/edenflowers version` prints "edenflowers 1.7.0"
    version=$(ssh -T edenflowers-production "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers version" | awk '{print "v"$2}') || version=unknown
    mkdir -p tmp
    file="tmp/production-$version-$(date +%Y%m%dT%H%M%S).dump"
    # Disable SSH's pseudo-terminal with -T so terminal newline conversion cannot corrupt the binary dump.
    ssh -T edenflowers-production "sudo -u postgres pg_dump -Fc edenflowers_store_prod" > "$file.partial"
    pg_restore -f /dev/null "$file.partial" || { echo "$file.partial cannot be read back, so it is no backup" >&2; exit 1; }
    mv "$file.partial" "$file"
    ls -lh "$file"

# Create a batch of pass-it-on codes on production and render their cards as a print shop PDF in tmp/, e.g. `just print-cards "Skicka vidare 2026-11" 100`
[group('production')]
print-cards name count:
    #!/usr/bin/env bash
    set -euo pipefail
    # Checked before the codes exist, so a missing tool doesn't leave an unprinted batch behind
    [ -f priv/receipts/icc/PSOcoated_v3.icc ] || { echo "No print profile. See \`mix help pass_it_on_cards\`." >&2; exit 1; }
    command -v gs >/dev/null || { echo "Ghostscript is missing: brew install ghostscript" >&2; exit 1; }
    just backup
    slug=$(echo "{{ name }}" | tr '[:upper:] ' '[:lower:]-')
    codes="tmp/codes-$slug.txt"
    ssh -T edenflowers-production "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers rpc 'Edenflowers.Pricing.create_pass_it_on_batch!(\"{{ name }}\", {{ count }}, actor: Edenflowers.Actors.system_actor()) |> Enum.each(&IO.puts/1)'" > "$codes"
    [ "$(wc -l < "$codes" | tr -d ' ')" = "{{ count }}" ] || { echo "Expected {{ count }} codes in $codes, see what came back there" >&2; exit 1; }
    mix pass_it_on_cards "$codes" "tmp/cards-$slug.pdf"

# Pull and restart production's other services (cloudflared, imgproxy, umami, papra). Restarting cloudflared drops the site for a few seconds
[group('production')]
update-services:
    # Leave the app to `just deploy`: pulling its latest image here would skip migrations and undo a rollback.
    ssh -T edenflowers-production 'cd /opt/edenflowers_store && services=$(docker compose config --services | grep -vx app) && docker compose pull $services && docker compose up -d --no-deps $services && docker image prune -f'

# Toggle production's maintenance mode after a prompt, restarting the app (the Maintenance workflow does the same from GitHub)
[group('production')]
maintenance:
    ./scripts/maintenance.sh

# Push images/ to production, deleting server photos removed locally (up to MAX_DELETE)
[group('production')]
push-images:
    ./scripts/push-images.sh

# Download production's images/ (not admin uploads) without deleting anything here
[group('production')]
pull-images:
    rsync -avz --exclude=/uploads/ --exclude=.DS_Store edenflowers-production:/opt/edenflowers_store/images/ images/

# Tail the production app logs
[group('production')]
tail-logs:
    ssh edenflowers-production 'cd /opt/edenflowers_store && docker compose logs -f --tail=200 app'

# Open a remote IEx console on production
[group('production')]
open-console:
    ssh -t edenflowers-production 'cd /opt/edenflowers_store && docker compose exec app /app/bin/edenflowers remote'

# Print the open review notes left with Option+Click (`just feedback local` reads the dev database)
[group('production')]
feedback where="production":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ "{{ where }}" = local ]; then
        mix run -e 'IO.puts(Edenflowers.Feedback.open_notes_markdown())'
    else
        ssh -T edenflowers-production "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers rpc 'IO.puts(Edenflowers.Feedback.open_notes_markdown())'"
    fi

# Print the most recent unresolved ErrorTracker errors in production
[group('production')]
errors limit="20":
    ssh -T edenflowers-production "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers rpc 'import Ecto.Query; Edenflowers.Repo.all(from e in ErrorTracker.Error, where: e.status == :unresolved, order_by: [desc: e.last_occurrence_at], limit: {{ limit }}) |> Enum.each(fn e -> IO.puts(\"#{e.id} | #{e.last_occurrence_at} | #{e.kind}: #{String.slice(e.reason, 0, 200)} | #{e.source_function}\") end)'"

# Mark ErrorTracker errors resolved in production. No backup first: it only sets their status, and a new occurrence unresolves them
[group('production')]
resolve-errors +ids:
    ssh -T edenflowers-production "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers rpc 'for id <- ~w({{ ids }}) do case Edenflowers.Repo.get!(ErrorTracker.Error, id) do %{status: :resolved} -> IO.puts(\"Already resolved ##{id}\"); error -> {:ok, _} = ErrorTracker.resolve(error); IO.puts(\"Resolved ##{id}\") end end'"

# Mark review notes as dealt with in production. No backup first: it only sets their resolved_at
[group('production')]
resolve-feedback +numbers:
    ssh -T edenflowers-production "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers rpc 'for number <- ~w({{ numbers }}), do: IO.puts(\"Resolved ##{Edenflowers.Feedback.resolve_note!(number, actor: Edenflowers.Actors.system_actor()).number}\")'"
