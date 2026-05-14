#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

source scripts/lib/ui.sh

section "Preflight checks"

if [[ -n "$(git status --porcelain)" ]]; then
  fail "working directory is not clean — commit or stash changes first"
fi
ok "working tree clean"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "main" ]]; then
  fail "must deploy from main (currently on $BRANCH)"
fi
ok "on main"

printf '  %sfetching origin...%s\n' "$DIM" "$RESET"
git fetch --quiet origin main --tags

LOCAL="$(git rev-parse main)"
REMOTE="$(git rev-parse origin/main)"
BASE="$(git merge-base main origin/main)"

if [[ "$LOCAL" != "$REMOTE" ]]; then
  if [[ "$LOCAL" == "$BASE" ]]; then
    fail "local main is behind origin/main — run 'git pull --ff-only' first"
  elif [[ "$REMOTE" == "$BASE" ]]; then
    fail "local main has unpushed commits — push them before deploying"
  else
    fail "local main and origin/main have diverged — reconcile before deploying"
  fi
fi
ok "local main matches origin"

CURRENT="$(grep -E 'version: "[0-9]+\.[0-9]+\.[0-9]+"' mix.exs | head -1 | sed -E 's/.*version: "([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')"
if [[ -z "$CURRENT" ]]; then
  fail "could not read current version from mix.exs"
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
PATCH_NEXT="$MAJOR.$MINOR.$((PATCH + 1))"
MINOR_NEXT="$MAJOR.$((MINOR + 1)).0"
MAJOR_NEXT="$((MAJOR + 1)).0.0"

VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  section "Version selection"
  printf '  current: %s%s%s\n\n' "$BOLD" "$CURRENT" "$RESET"
  echo "  1) patch → $PATCH_NEXT  (bug fixes)"
  echo "  2) minor → $MINOR_NEXT  (new features)"
  echo "  3) major → $MAJOR_NEXT  (breaking changes)"
  echo
  read -r -p "  Choice [1]: " CHOICE
  CHOICE="${CHOICE:-1}"

  case "$CHOICE" in
    1) VERSION="$PATCH_NEXT" ;;
    2) VERSION="$MINOR_NEXT" ;;
    3) VERSION="$MAJOR_NEXT" ;;
    *) fail "invalid choice" ;;
  esac
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  fail "version must be in semver format (e.g. 0.2.0)"
fi

TAG="v$VERSION"

if git rev-parse "$TAG" &>/dev/null; then
  fail "tag $TAG already exists"
fi

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

section "Running precommit checks"
mix precommit

section "Tagging release"
# Use -i.bak + rm so it works on both BSD sed (macOS) and GNU sed (Linux).
sed -i.bak "s/version: \"[0-9]*\.[0-9]*\.[0-9]*\"/version: \"$VERSION\"/" mix.exs
rm -f mix.exs.bak
ok "mix.exs → $VERSION"

git add mix.exs
git commit --quiet -m "Bump version to $TAG"
ok "commit created"
git tag "$TAG"
ok "tag $TAG created"

section "Ready to push"
echo "  main → $(git rev-parse --short HEAD)  $(git log -1 --pretty=%s)"
echo "  tag  → $TAG"
echo
read -r -p "  Proceed with push? [y/N] " REPLY
if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
  printf '\n  %saborted — cleaning up local commit and tag%s\n' "$DIM" "$RESET"
  git tag -d "$TAG" >/dev/null
  git reset --hard --quiet HEAD~1
  exit 1
fi

SKIP_HOOKS=1 git push --atomic origin main "refs/tags/$TAG"

printf '\n%s%s✓ Deployed %s%s  %sGitHub Actions will build and deploy the Docker image.%s\n' \
  "$BOLD" "$GREEN" "$TAG" "$RESET" "$DIM" "$RESET"
