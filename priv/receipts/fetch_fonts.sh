#!/usr/bin/env bash
# Fetch the two brand fonts as static .ttf files via the Google Fonts CSS2
# API. We resolve the CSS once, extract per-weight .ttf URLs, and download
# them. Static weights are required because Typst 0.14 emits warnings for
# variable fonts (and renders them imperfectly).
#
# Run once per checkout — the .ttf files are .gitignored so each
# environment fetches its own copy.
set -euo pipefail

cd "$(dirname "$0")/fonts"

# Helper — given a CSS2 family spec and a parallel list of output names,
# resolve the CSS, extract .ttf URLs in document order, and download to
# the named files. CSS2 returns weights in the order requested, so the
# index alignment is deterministic.
#
# Note: macOS ships bash 3.2 (no `mapfile`), so we read with a while loop.
fetch_family() {
  local spec="$1"
  shift
  local names=("$@")

  local urls=()
  while IFS= read -r url; do
    urls+=("$url")
  done < <(
    curl -fsSL "https://fonts.googleapis.com/css2?${spec}" \
      | grep -oE "https://[^)]+\.ttf"
  )

  if [ "${#urls[@]}" -ne "${#names[@]}" ]; then
    echo "fetch_family: expected ${#names[@]} URLs for '$spec', got ${#urls[@]}" >&2
    return 1
  fi

  local i
  for i in "${!urls[@]}"; do
    curl -fsSL -o "${names[$i]}" "${urls[$i]}"
  done
}

# Open Sans — 400 / 600 / 700, roman + italic.
fetch_family \
  "family=Open+Sans:ital,wght@0,400;0,600;0,700;1,400;1,600;1,700&display=swap" \
  OpenSans-Regular.ttf \
  OpenSans-SemiBold.ttf \
  OpenSans-Bold.ttf \
  OpenSans-Italic.ttf \
  OpenSans-SemiBoldItalic.ttf \
  OpenSans-BoldItalic.ttf

# Crimson Text — 400 / 600 / 700, roman + italic.
fetch_family \
  "family=Crimson+Text:ital,wght@0,400;0,600;0,700;1,400;1,600;1,700&display=swap" \
  CrimsonText-Regular.ttf \
  CrimsonText-SemiBold.ttf \
  CrimsonText-Bold.ttf \
  CrimsonText-Italic.ttf \
  CrimsonText-SemiBoldItalic.ttf \
  CrimsonText-BoldItalic.ttf

# Remove any stale variable-font files left from earlier runs.
rm -f OpenSans.ttf

echo "Fonts fetched into $(pwd)"
ls -1
