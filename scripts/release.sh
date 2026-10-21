#!/bin/bash
# Publish a GitHub release for an already-pushed tag, with notes drafted by Claude
# from the commits since the previous tag. Rerun it for any tag that lacks a release.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

source scripts/lib/ui.sh

TAG="${1:-}"
[[ -n "$TAG" ]] || fail "usage: scripts/release.sh <tag>"
git rev-parse --verify --quiet "refs/tags/$TAG" >/dev/null || fail "tag $TAG does not exist"

if gh release view "$TAG" &>/dev/null; then
  fail "release $TAG already exists"
fi

PREVIOUS="$(git describe --tags --abbrev=0 "$TAG^")"

section "Drafting release notes for $TAG (since $PREVIOUS)"

COMMITS="$(git log --no-merges --invert-grep --grep='^Bump version' \
  --format='## %s%n%n%b' "$PREVIOUS..$TAG" | grep -v '^Claude-Session:')"

PROMPT="Write release notes for $TAG of Eden Flowers, a florist's online shop with an admin.
The commits since $PREVIOUS are on stdin. Write a few bullets, grouped under short bold
headings by area (e.g. Orders, Courses, Admin, Store). Describe what changed for the people
using the shop and its admin, not how the code changed. Leave out internal-only work such as
tests, seeds, specs, refactors and tooling. If nothing user-facing changed, say so in one line.
Output only the Markdown notes, with no title and no preamble."

NOTES="$(mktemp -t release-notes)"
trap 'rm -f "$NOTES"' EXIT

# .env exports the app's ANTHROPIC_API_KEY (just loads it too); drop it so claude uses the claude.ai login
printf '%s\n' "$COMMITS" | env -u ANTHROPIC_API_KEY claude -p "$PROMPT" --tools "" --no-session-persistence > "$NOTES"
ok "draft written"

"${VISUAL:-${EDITOR:-vi}}" "$NOTES"

if ! grep -q '[^[:space:]]' "$NOTES"; then
  fail "notes are empty, release not published"
fi

gh release create "$TAG" --verify-tag --title "$TAG" --notes-file "$NOTES"
ok "release $TAG published"
