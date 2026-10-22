#!/bin/bash
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

source scripts/lib/ui.sh

latest_run_id() {
  gh run list --workflow=deploy.yml --commit "$(git rev-parse HEAD)" --limit 1 --json databaseId -q '.[0].databaseId // 0'
}

# A new run takes a few seconds to appear.
watch_deploy() {
  local sha run_id=""
  sha="$(git rev-parse HEAD)"
  printf '  %swaiting for the GitHub Actions run...%s\n' "$DIM" "$RESET"
  for _ in {1..30}; do
    run_id="$(latest_run_id)"
    ((run_id > 0)) && break
    run_id=""
    sleep 2
  done
  if [[ -z "$run_id" ]]; then
    printf "  %s✗ no deploy run found for %s, try 'just deploy-watch' in a moment%s\n" "$RED" "$sha" "$RESET" >&2
    return 1
  fi

  gh run watch "$run_id" --compact --exit-status
}

run_checks() {
  section "Installing deps"
  mix deps.get
  ok "deps installed"

  section "Downloading locales"
  mix localize.download_locales
  ok "locales downloaded"

  section "Running precommit checks"
  mix precommit
}

section "Preflight checks"

if [[ -n "$(git status --porcelain)" ]]; then
  fail "working directory is not clean — commit or stash changes first"
fi
ok "working tree clean"

BRANCH="$(git rev-parse --abbrev-ref HEAD)"

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

if [[ "$BRANCH" != "main" ]]; then
  fail "must deploy from main (currently on $BRANCH)"
fi
ok "on main"

printf '  %sfetching origin...%s\n' "$DIM" "$RESET"
git fetch --quiet origin main --tags

LOCAL="$(git rev-parse main)"
REMOTE="$(git rev-parse origin/main)"
BASE="$(git merge-base main origin/main)"

# Unpushed commits are fine: the atomic push below sends them with the release tag.
if [[ "$REMOTE" != "$BASE" ]]; then
  if [[ "$LOCAL" == "$BASE" ]]; then
    fail "local main is behind origin/main — run 'git pull --ff-only' first"
  else
    fail "local main and origin/main have diverged — reconcile before deploying"
  fi
fi
ok "local main is up to date with or ahead of origin"

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

run_checks

# Before tagging, so a failed sync doesn't leave a local version-bump commit and tag behind.
scripts/sync-images.sh

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

# Taken last, so the backup is as close as possible to the migrations it guards against.
section "Backing up production database"
if ! just backup; then
  git tag -d "$TAG" >/dev/null
  git reset --hard --quiet HEAD~1
  fail "backup failed, cleaned up local commit and tag. Nothing was pushed."
fi
ok "rollback: just rollback v$CURRENT [that dump]"

SKIP_HOOKS=1 git push --atomic origin main "refs/tags/$TAG"

printf '\n%s%s✓ Pushed %s%s  %sGitHub Actions will build and deploy the Docker image.%s\n' \
  "$BOLD" "$GREEN" "$TAG" "$RESET" "$DIM" "$RESET"

# Publish the release only once it is live, so GitHub never announces a version production isn't running.
section "Watching deploy"
if ! watch_deploy; then
  fail "deploy of $TAG did not succeed. Once it is live (fix, or 'gh run rerun'), publish notes with: scripts/release.sh $TAG"
fi
ok "$TAG deployed to production"

# The deploy has succeeded, so a failed release mustn't look like a failed deploy.
if ! scripts/release.sh "$TAG"; then
  printf '\n  %srelease notes not published, rerun with: scripts/release.sh %s%s\n' "$DIM" "$TAG" "$RESET"
fi
