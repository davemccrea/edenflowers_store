#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

source scripts/lib/ui.sh
source .env

section "Resetting dev database"
mix ecto.drop
ok "dropped"
mix ash.setup
ok "schema set up"
mix run priv/repo/seeds.exs
ok "seeded"

section "Resetting test database"
MIX_ENV=test mix ecto.drop
ok "dropped"
MIX_ENV=test mix ash.setup
ok "schema set up"

printf '\n%s%s✓ Databases reset%s\n' "$BOLD" "$GREEN" "$RESET"
