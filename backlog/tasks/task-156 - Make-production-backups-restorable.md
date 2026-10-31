---
id: TASK-156
title: Make production backups restorable
status: done
assignee: []
created_date: '2026-10-31 11:40'
updated_date: '2026-10-31 11:51'
labels:
  - spec
  - admin
dependencies: []
priority: high
type: bug
ordinal: 291000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`just backup` dumps from production cannot be read back: `pg_restore` segfaults on every dump in `tmp/`, so `just rollback <tag> <dump>` has no working data to restore.

**Why:** a backup that cannot be restored is no backup. A bad deploy or data fix would lose orders, customers and payments with no way back.

Found on 2026-10-31: `pg_restore -l` (and plain restores) exit 139 on `tmp/production-v1.22.0-20261030T234136.dump` and on the oldest, `tmp/production-v1.13.4-20261025T231801.dump`. This happens with Homebrew Postgres 17.11 and with the `postgres:16`, `postgres:17` and `postgres:18` Docker images. A `pg_dump -Fc` of the local `edenflowers_dev` database, read with the same Homebrew `pg_restore`, works, so the tools are fine and the problem is in the production dumps or how they are made. File headers look normal (`PGDMP`, archive version 1.15). Atuin history shows no successful restore of a production dump ever.

Open questions:
- Is it the dump stream (`ssh edenflowers-production "sudo -u postgres pg_dump -Fc ..." > file` in the `backup` recipe), the server pg_dump version, or a corrupt object in the database?
- Are the nightly server-side dumps in `/opt/edenflowers_store/backups/` affected too?
- Does `just rollback` need changes as well, and should `just backup` check its dump (e.g. `pg_restore -l`) before reporting success?
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A fresh `just backup` dump restores into a scratch local database with matching row counts for orders, line_items and payments
- [x] #2 The nightly server-side dump restores too, or is shown to be unaffected
- [x] #3 `just backup` fails loudly when its dump cannot be read back
- [x] #4 `just rollback` is tested end to end against a dump, in a way that does not touch production
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Root cause: ~/.ssh/config sets RequestTTY yes for edenflowers-production, so ssh in `just backup` ran pg_dump on a pty whose ONLCR turned every LF byte into CRLF, corrupting the binary archive. Undoing it (s/\r\n/\n/g) restored the v1.22.1 dump with 13 orders, 15 line_items, 1 payment.
1. ssh -T in backup and rollback
2. just backup reads the whole dump back (pg_restore -f /dev/null) before keeping it
3. Restore step moves to scripts/restore-db.sh, which checks the dump before dropping the database; rollback runs it on production and `just check-restore <dump>` runs it in a throwaway postgres:16 container
4. Old corrupt dumps in tmp/ deleted (David's call)
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Nightly server-side dump (edenflowers_store_prod_20261031T020001.dump) reads back fully with pg_restore on the server: unaffected, as it never passes through ssh.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-31 11:47

---

Control: heroku_db.dump (old site, archive version 1.16, Apr 2026) restores fine with the same Homebrew pg_restore 17.11. Every production dump that crashes is archive version 1.15, so check which pg_dump version the server runs.

---

author: @claude
created: 2026-10-31 11:50

---

Fresh just backup (tmp/production-v1.23.0-20261031T135023.dump) restored via just check-restore: orders 14, line_items 16, payments 1, matching production.

---
<!-- COMMENTS:END -->
