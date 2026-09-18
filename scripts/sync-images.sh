#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

source scripts/lib/ui.sh

TARGET="${1:-all}"

case "$TARGET" in
  staging) HOSTS=(edenflowers-staging) ;;
  production) HOSTS=(edenflowers-production) ;;
  all) HOSTS=(edenflowers-staging edenflowers-production) ;;
  *) fail "target must be staging, production or all" ;;
esac

section "Preflight checks"

# --delete mirrors images/ onto the server, so an empty local dir would wipe it.
if [[ -z "$(ls -A images 2>/dev/null)" ]]; then
  fail "images/ is missing or empty"
fi
ok "images/ has $(find images -type f | wc -l | tr -d ' ') files"

# macOS stores non-ASCII filenames as NFD, which won't match NFC slugs in code.
NON_ASCII="$(LC_ALL=C find images -name '*[! -~]*')"
if [[ -n "$NON_ASCII" ]]; then
  fail "rename non-ASCII filenames first:"$'\n'"$NON_ASCII"
fi
ok "filenames are ASCII"

for HOST in "${HOSTS[@]}"; do
  section "Syncing to $HOST"
  # imgproxy returns 500 for files it can't read, so force world-readable modes.
  rsync -avz --delete --chmod=D755,F644 images "$HOST:/opt/edenflowers_store/"
  ok "synced"
done
