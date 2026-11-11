#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

source scripts/lib/ui.sh

# Same steps as .github/workflows/maintenance.yml.
APP_DIR=/opt/edenflowers_store

CURRENT="$(ssh -T edenflowers-production "cat $APP_DIR/maintenance.env 2>/dev/null" | sed -nE 's/^MAINTENANCE_MODE=(true|false)$/\1/p')"
case "$CURRENT" in
  true) STATE=on; NEXT=false; NEXT_STATE=off ;;
  false) STATE=off; NEXT=true; NEXT_STATE=on ;;
  *) fail "could not read $APP_DIR/maintenance.env on production, run just provision first" ;;
esac

section "Maintenance mode"
printf '  currently: %s%s%s\n\n' "$BOLD" "$STATE" "$RESET"
read -r -p "  Turn it $NEXT_STATE and restart the app? [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || fail "cancelled, nothing changed"

section "Restarting the app"
ssh -T edenflowers-production "cd $APP_DIR && echo MAINTENANCE_MODE=$NEXT > maintenance.env && docker compose up -d app"
# Suppress expected HTTP errors during startup; Cloudflare returns 502 until the app is ready.
curl -fs --retry 60 --retry-delay 2 --retry-all-errors https://edenflowers.fi/health > /dev/null ||
  fail "the app did not come back within two minutes, check just tail-logs"
ok "the app is back up"

printf '\n%s%s✓ Maintenance mode is %s%s\n' "$BOLD" "$GREEN" "$NEXT_STATE" "$RESET"
