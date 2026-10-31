#!/bin/bash
# Replace the database a `pg_dump -Fc` archive was taken from with that archive.
# Run as a Postgres superuser. `just rollback` runs it on production, `just check-restore` locally.
# Usage: restore-db.sh <dump>
set -euo pipefail

dump=$1
# Read the whole archive before dropping anything, so a corrupt dump leaves the database alone
pg_restore -f /dev/null "$dump"
db=$(pg_restore --list "$dump" | sed -n 's/^;[[:space:]]*dbname: //p')
dropdb --force --if-exists "$db"
# --create restores the database's owner and grants along with it
pg_restore --create --exit-on-error -d postgres "$dump"
