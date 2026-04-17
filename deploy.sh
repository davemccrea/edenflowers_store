#!/bin/bash
set -euo pipefail

VERSION="${1:-}"

if [[ -z "$VERSION" ]]; then
  echo "Usage: ./deploy.sh <version>  (e.g. ./deploy.sh 0.2.0)"
  exit 1
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

if [[ -n "$(git status --porcelain)" ]]; then
  echo "Error: working directory is not clean — commit or stash changes first"
  exit 1
fi

if [[ -f .env ]]; then
  set -a
  source .env
  set +a
fi

echo "Compiling..."
mix compile --warnings-as-errors

echo "Running tests..."
mix test

sed -i '' "s/version: \"[0-9]*\.[0-9]*\.[0-9]*\"/version: \"$VERSION\"/" mix.exs

echo "Updated mix.exs to version $VERSION"

git add mix.exs
git commit -m "Bump version to $TAG"
git tag "$TAG"
git push origin main "$TAG"

echo "Deployed $TAG — GitHub Actions will build and deploy the Docker image."
