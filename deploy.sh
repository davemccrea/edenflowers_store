#!/bin/bash
set -euo pipefail

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: working directory is not clean — commit or stash changes first"
  exit 1
fi

BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [[ "$BRANCH" != "main" ]]; then
  echo "Error: must deploy from main (currently on $BRANCH)"
  exit 1
fi

echo "Fetching origin to verify local main is up-to-date..."
git fetch origin main --tags

LOCAL="$(git rev-parse main)"
REMOTE="$(git rev-parse origin/main)"
BASE="$(git merge-base main origin/main)"

if [[ "$LOCAL" != "$REMOTE" ]]; then
  if [[ "$LOCAL" == "$BASE" ]]; then
    echo "Error: local main is behind origin/main — run 'git pull --ff-only' first"
  elif [[ "$REMOTE" == "$BASE" ]]; then
    echo "Error: local main has unpushed commits — push them before deploying"
  else
    echo "Error: local main and origin/main have diverged — reconcile before deploying"
  fi
  exit 1
fi

CURRENT="$(grep -E 'version: "[0-9]+\.[0-9]+\.[0-9]+"' mix.exs | head -1 | sed -E 's/.*version: "([0-9]+\.[0-9]+\.[0-9]+)".*/\1/')"
if [[ -z "$CURRENT" ]]; then
  echo "Error: could not read current version from mix.exs"
  exit 1
fi

IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
PATCH_NEXT="$MAJOR.$MINOR.$((PATCH + 1))"
MINOR_NEXT="$MAJOR.$((MINOR + 1)).0"
MAJOR_NEXT="$((MAJOR + 1)).0.0"

VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  echo
  echo "Current version: $CURRENT"
  echo
  echo "Select release type:"
  echo "  1) patch  → $PATCH_NEXT  (bug fixes)"
  echo "  2) minor  → $MINOR_NEXT  (new features)"
  echo "  3) major  → $MAJOR_NEXT  (breaking changes)"
  echo
  read -r -p "Choice [1]: " CHOICE
  CHOICE="${CHOICE:-1}"

  case "$CHOICE" in
    1) VERSION="$PATCH_NEXT" ;;
    2) VERSION="$MINOR_NEXT" ;;
    3) VERSION="$MAJOR_NEXT" ;;
    *) echo "Error: invalid choice"; exit 1 ;;
  esac
fi

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Error: version must be in semver format (e.g. 0.2.0)"
  exit 1
fi

TAG="v$VERSION"

if git rev-parse "$TAG" &>/dev/null; then
  echo "Error: tag $TAG already exists"
  exit 1
fi

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

echo "Running precommit checks..."
mix precommit

sed -i '' "s/version: \"[0-9]*\.[0-9]*\.[0-9]*\"/version: \"$VERSION\"/" mix.exs

echo "Updated mix.exs to version $VERSION"

git add mix.exs
git commit -m "Bump version to $TAG"
git tag "$TAG"

echo
echo "About to push to origin:"
echo "  main → $(git rev-parse --short HEAD) ($(git log -1 --pretty=%s))"
echo "  tag  → $TAG"
echo
read -r -p "Proceed with push? [y/N] " REPLY
if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
  echo "Aborted. Cleaning up local commit and tag..."
  git tag -d "$TAG"
  git reset --hard HEAD~1
  exit 1
fi

SKIP_HOOKS=1 git push --atomic origin main "refs/tags/$TAG"

echo "Deployed $TAG — GitHub Actions will build and deploy the Docker image."
