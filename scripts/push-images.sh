#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

source scripts/lib/ui.sh

section "Preflight checks"

if [[ ! -d images ]]; then
  fail "images/ is missing"
fi
PHOTO_COUNT="$(find images -type f -not -path 'images/uploads/*' | wc -l | tr -d ' ')"
# The push runs with --delete, so an empty images/ (a fresh clone, or a machine
# without the photos) would wipe every photo on the server.
if [[ "$PHOTO_COUNT" -eq 0 ]]; then
  fail "images/ has no photos, so pushing would delete every photo on the server"
fi
ok "images/ has $PHOTO_COUNT files"

# macOS stores non-ASCII filenames as NFD, which won't match NFC slugs in code.
NON_ASCII="$(LC_ALL=C find images -name '*[! -~]*')"
if [[ -n "$NON_ASCII" ]]; then
  fail "rename non-ASCII filenames first:"$'\n'"$NON_ASCII"
fi
ok "filenames are ASCII"

section "Pushing to edenflowers-production"
# imgproxy returns 500 for files it can't read, so force world-readable modes.
# uploads/ is the app's own folder on the server, so it's never pushed to, and
# --delete leaves excluded paths alone.
PUSH=(rsync -az --chmod=D755,F644 --delete --exclude=/images/uploads/ --exclude=.DS_Store
  images edenflowers-production:/opt/edenflowers_store/)

# rsync's own --max-delete still deletes up to the limit before stopping, so
# count the deletions in a dry run and refuse before anything is removed.
MAX_DELETE="${MAX_DELETE:-0}"
DELETED_FILES="$("${PUSH[@]}" --dry-run --itemize-changes | grep '^\*deleting' || true)"
DELETIONS="$(grep -c . <<<"$DELETED_FILES" || true)"
if [[ "$DELETIONS" -gt "$MAX_DELETE" ]]; then
  fail "the push would delete $DELETIONS files from the server (limit $MAX_DELETE):"$'\n'"$DELETED_FILES"$'\n'"If that's intended, rerun with MAX_DELETE=$DELETIONS."$'\n'"If this machine just never had them, run just pull-images first."
fi

"${PUSH[@]}" -v
ok "synced"
