#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

source scripts/lib/ui.sh

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

section "Syncing to edenflowers-production"
# imgproxy returns 500 for files it can't read, so force world-readable modes.
# uploads/ is the app's own folder on the server, so it's never pushed to, and
# --delete leaves excluded paths alone. --max-delete stops a half-empty
# images/ from wiping the server: rsync fails instead, and so does the deploy.
rsync -avz --chmod=D755,F644 --delete --max-delete=20 --exclude=/images/uploads/ --exclude=.DS_Store \
  images edenflowers-production:/opt/edenflowers_store/
ok "synced"

# The admin's uploads live only on the production server, so keep a copy here.
# No --delete: a photo lost on the server stays on this machine.
section "Pulling uploads from edenflowers-production"
rsync -avz edenflowers-production:/opt/edenflowers_store/images/uploads/ images/uploads/
ok "pulled"
