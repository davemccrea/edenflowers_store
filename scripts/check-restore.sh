#!/bin/bash
# Restore a production dump the way `just rollback` does, into a throwaway postgres:16 container
# (production's major version), and print the row counts that matter most.
# Usage: scripts/check-restore.sh <dump>
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

source scripts/lib/ui.sh

[[ $# -eq 1 ]] || fail "usage: just check-restore <dump>"
DUMP=$1
[[ -s "$DUMP" ]] || fail "no dump at $DUMP"

section "Starting a scratch Postgres"
container=$(docker run -d --rm -e POSTGRES_HOST_AUTH_METHOD=trust postgres:16)
trap 'docker stop "$container" >/dev/null' EXIT
# The image's temporary initialization server only listens on a Unix socket.
# Wait for TCP so the restore starts after the final server is ready.
until docker exec "$container" pg_isready -q -h 127.0.0.1 -U postgres; do sleep 1; done
ok "started"

section "Restoring $DUMP"
docker cp -q "$DUMP" "$container:/tmp/rollback.dump"
# Recreate the dump's owner roles because this scratch server, unlike production, starts without them.
for role in $(pg_restore -f - --schema-only "$DUMP" | sed -n 's/.* OWNER TO \(.*\);$/\1/p' | sort -u); do
  docker exec -u postgres "$container" sh -c "createuser '$role' 2>/dev/null || true"
done
docker exec -i -u postgres "$container" bash -s -- /tmp/rollback.dump < scripts/restore-db.sh
ok "restored"

db=$(pg_restore --list "$DUMP" | sed -n 's/^;[[:space:]]*dbname: //p')
docker exec -u postgres "$container" psql -d "$db" -c \
  "select 'orders' as table, count(*) from orders
   union all select 'line_items', count(*) from line_items
   union all select 'payments', count(*) from payments"
