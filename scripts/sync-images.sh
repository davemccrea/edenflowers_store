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

# imgproxy tells browsers and Cloudflare to keep an image for a year, so a photo
# replaced under its old name would never show. `image/1` puts each file's hash
# in its URL, which changes the URL whenever the photo does.
section "Hashing images"
{
  echo "{"
  find images -type f -not -path 'images/uploads/*' -not -name .DS_Store | LC_ALL=C sort |
    while read -r file; do
      printf '  "%s": "%s"\n' "${file#images/}" "$(shasum -a 256 "$file" | cut -c1-8)"
    done | sed '$!s/$/,/'
  echo "}"
} > priv/image_hashes.json
if [[ -n "$(git status --porcelain priv/image_hashes.json)" ]]; then
  ok "hashes changed: commit priv/image_hashes.json and deploy, or the site keeps the old photos"
else
  ok "no photos changed"
fi

section "Syncing to edenflowers-production"
# imgproxy returns 500 for files it can't read, so force world-readable modes.
# uploads/ is the app's own folder on the server, so it's never pushed to, and
# --delete leaves excluded paths alone.
rsync -avz --chmod=D755,F644 --delete --exclude=/images/uploads/ --exclude=.DS_Store \
  images edenflowers-production:/opt/edenflowers_store/
ok "synced"

# The admin's uploads live only on the production server, so keep a copy here.
# --max-delete stops an emptied server folder from wiping this copy.
section "Pulling uploads from edenflowers-production"
rsync -avz --delete --max-delete=20 --exclude=.DS_Store \
  edenflowers-production:/opt/edenflowers_store/images/uploads/ images/uploads/
ok "pulled"
