#!/bin/bash
# Roll production back to a release tag, optionally restoring a database backup taken while it ran.
# Usage: scripts/rollback.sh <tag> [dump]
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

source scripts/lib/ui.sh

[[ $# -eq 1 || $# -eq 2 ]] || fail "usage: just rollback <tag> [dump]"
TAG=$1 DUMP=${2:-}
DB=edenflowers_store_prod
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null || fail "no tag $TAG, try 'git fetch --tags'"

if [[ -n "$DUMP" ]]; then
  [[ -s "$DUMP" ]] || fail "no dump at $DUMP"
  [[ "$DUMP" == *"$TAG"* ]] || echo "Warning: $DUMP was not taken while $TAG was running."
  echo "This replaces the production database with $DUMP and runs $TAG."
  echo "Anything written since that backup (orders, payments) is lost; check Stripe for payments to reconcile."
else
  # `bin/edenflowers version` prints "edenflowers 1.7.0"
  RUNNING=$(ssh edenflowers-production "cd /opt/edenflowers_store && docker compose exec -T app /app/bin/edenflowers version" | awk '{print "v"$2}')
  git rev-parse -q --verify "refs/tags/$RUNNING" >/dev/null || fail "production runs $RUNNING, which has no local tag"
  MIGRATIONS=$(git diff --name-only --diff-filter=A "$TAG" "$RUNNING" -- priv/repo/migrations)
  echo "This runs $TAG on production against the database as $RUNNING left it."
  if [[ -n "$MIGRATIONS" ]]; then
    echo "$TAG will run without these migrations. If one drops or renames a column, or adds a NOT NULL one, pass a dump instead:"
    echo "$MIGRATIONS"
  fi
fi
read -r -p "Roll back production? [y/N] " REPLY
[[ "$REPLY" =~ ^[yY]$ ]] || exit 1

if [[ -n "$DUMP" ]]; then
  section "Backing up production"
  # The rollback itself must be undoable
  just backup

  section "Uploading $DUMP"
  ssh -T edenflowers-production "sudo -u postgres tee /tmp/rollback.dump >/dev/null" < "$DUMP"
  ok "uploaded"
fi

section "Starting $TAG"
ssh -T edenflowers-production bash -s -- "$DB" "${TAG#v}" "$([[ -n "$DUMP" ]] && echo restore || echo keep)" <<'EOF'
set -euo pipefail
db=$1 version=$2 database=$3
cd /opt/edenflowers_store
# Compose runs a moving tag (latest), so point it at the old release's image
image=$(docker compose config --images app)
docker pull "${image%:*}:$version"
docker tag "${image%:*}:$version" "$image"
docker compose stop app
if [[ "$database" == restore ]]; then
  sudo -u postgres dropdb --force "$db"
  # --create restores the database's owner and grants along with it
  sudo -u postgres pg_restore --create --exit-on-error -d postgres /tmp/rollback.dump
  sudo rm /tmp/rollback.dump
fi
docker compose up -d app
for _ in $(seq 60); do
  docker compose exec -T app /app/bin/edenflowers rpc ':ok' >/dev/null 2>&1 && exit 0
  sleep 2
done
echo "The app didn't come up within 2 minutes" >&2; exit 1
EOF
ok "production is on $TAG. The next deploy pulls the moving tag again."
