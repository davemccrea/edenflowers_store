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

if [[ ! -d images ]]; then
  fail "images/ is missing"
fi
ok "images/ has $(find images -type f -not -path 'images/uploads/*' | wc -l | tr -d ' ') files"

# macOS stores non-ASCII filenames as NFD, which won't match NFC slugs in code.
NON_ASCII="$(LC_ALL=C find images -name '*[! -~]*')"
if [[ -n "$NON_ASCII" ]]; then
  fail "rename non-ASCII filenames first:"$'\n'"$NON_ASCII"
fi
ok "filenames are ASCII"

for HOST in "${HOSTS[@]}"; do
  section "Syncing to $HOST"
  # imgproxy returns 500 for files it can't read, so force world-readable modes.
  # No --delete: the server holds photos uploaded in the admin that aren't here.
  # uploads/ is the app's own folder on the server, so it's never pushed to.
  rsync -avz --chmod=D755,F644 --exclude=/images/uploads/ images "$HOST:/opt/edenflowers_store/"
  ok "synced"
done
