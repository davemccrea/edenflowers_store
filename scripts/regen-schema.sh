#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

source scripts/lib/ui.sh
source .env

section "Dropping dev database"
mix ecto.drop
ok "dropped"

section "Removing migrations and resource snapshots"
find priv/repo/migrations -type f ! -name ".formatter.exs" -delete
rm -rf priv/resource_snapshots
ok "cleared"

section "Regenerating migrations from Ash resources"
mix ash_postgres.generate_migrations initial
sleep 1
mix oban.install --yes
sleep 1
# Write the migration directly: error_tracker.install also appends a duplicate dashboard route to the router.
cat > "priv/repo/migrations/$(date -u +%Y%m%d%H%M%S)_add_error_tracker.exs" <<'EOF'
defmodule Edenflowers.Repo.Migrations.AddErrorTracker do
  use Ecto.Migration

  def up, do: ErrorTracker.Migration.up()
  def down, do: ErrorTracker.Migration.down(version: 1)
end
EOF
ok "migrations regenerated"

section "Setting up dev database"
mix ash.setup
ok "schema set up"

section "Seeding dev database"
mix run priv/repo/seeds.exs
ok "seeded"

printf '\n%s%s✓ Schema rebuilt%s\n' "$BOLD" "$GREEN" "$RESET"
