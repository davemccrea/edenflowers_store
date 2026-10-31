#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

source scripts/lib/ui.sh

VARS=infra/group_vars/all/vars.yml

CURRENT="$(sed -nE 's/^maintenance_mode: (true|false)$/\1/p' "$VARS")"
case "$CURRENT" in
  true) STATE=on; NEXT=false; NEXT_STATE=off ;;
  false) STATE=off; NEXT=true; NEXT_STATE=on ;;
  *) fail "could not read maintenance_mode from $VARS" ;;
esac

section "Maintenance mode"
printf '  currently: %s%s%s\n\n' "$BOLD" "$STATE" "$RESET"
read -r -p "  Turn it $NEXT_STATE and provision production? [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || fail "cancelled, nothing changed"

# Use -i.bak + rm so it works on both BSD sed (macOS) and GNU sed (Linux).
sed -i.bak -E "s/^maintenance_mode: .*/maintenance_mode: $NEXT/" "$VARS"
rm -f "$VARS.bak"
git commit --quiet -m "Turn maintenance mode $NEXT_STATE" -- "$VARS"
ok "committed maintenance_mode: $NEXT"

section "Provisioning production"
just provision

printf '\n%s%s✓ Maintenance mode is %s%s\n' "$BOLD" "$GREEN" "$NEXT_STATE" "$RESET"
