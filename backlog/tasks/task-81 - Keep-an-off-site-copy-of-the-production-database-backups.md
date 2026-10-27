---
id: TASK-81
title: Keep off-site copies of the production database backups and uploaded photos
status: in-progress
assignee: []
created_date: '2026-10-21 08:32'
updated_date: '2026-10-27 07:05'
labels:
  - spec
  - admin
dependencies: []
priority: high
type: chore
ordinal: 163000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every nightly production database dump and the uploaded photos are copied to the Hetzner Storage Box, with about 30 days of snapshot history that survives a lost or compromised server.

**Why:** The only backups are the nightly pg_dump files in /opt/edenflowers_store/backups/ on the production server itself, so losing that server loses every order, customer and payment record along with its backups.

Decisions:
- rsync, not restic. Each dump is already a complete, dated, compressed file, so restic's snapshots and dedup add little. Restoring is copying a file back. The one thing restic would add is encryption at rest. Revisit if the box gets used for other things or that matters for GDPR.
- The server mirrors its backup folder, which the nightly cron already prunes to 30 days, to the box with `rsync -a --delete`. The Storage Box's automatic snapshots keep that history safe: they are managed in the Hetzner console, not over SSH, so a compromised server that wipes the mirror can't delete them.
- Use the main Storage Box account for now; defer a dedicated sub-account. Keep backups in the dedicated `edenflowers/` directory. Accept that the production server's transfer key can access the main account beyond that directory; independently managed snapshots remain required.
- Production only. Staging holds test data.
- Server work lives in `infra/roles/common/tasks/backups.yml`, next to the existing 02:00 pg_dump cron.

Related, already in this repo: `just backup` (dump to tmp/, named after the running release), `just rollback <tag> [dump]`, and the CLAUDE.md rule to back up before touching production.

Photo backups are in scope: mirror the production uploaded-photo directory nightly, alongside the database dumps. Use separate remote destinations `edenflowers/database/` and `edenflowers/photos/`; never run rsync --delete against their shared parent. Local dump pruning controls database mirror retention; Storage Box snapshots retain previous photo versions and deleted photos. Both transfers must succeed before the success heartbeat. Restore verification must cover both a database dump and original uploaded photos. Repository-managed images can be recovered from git and need not be duplicated.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A dump from the latest night is on the Storage Box
- [ ] #2 Storage Box snapshots give roughly 30 days of history
- [ ] #3 A missed or failed nightly copy sends an alert
- [ ] #4 Uploaded production photos are copied nightly to the Storage Box; snapshot recovery of a deleted photo is verified
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Database and uploaded-photo mirror implementation is ready for human provisioning in TASK-81.2. Local checks passed, but live transfers, snapshots, alerts and restores have not been verified.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-27 06:57

---

Confirmed with David: use rsync to mirror the existing complete, dated dump files, not restic. The nightly local pruning remains the single retention policy; rsync --delete propagates it to the Storage Box, so no separate remote pruning job is needed. Independently managed Storage Box snapshots remain required because the writable mirror also propagates accidental or malicious deletions.

---

author: @claude
created: 2026-10-27 07:00

---

David deferred the dedicated Storage Box sub-account. Use the main account for now. This supersedes the earlier sub-account requirement; account-wide key access is accepted, not directory-isolated.

---

author: @claude
created: 2026-10-27 07:00

---

David added photo backups to scope. Main Storage Box account remains the current decision. Existing root-level mirror destination must be split before adding photos, to avoid rsync --delete deleting the sibling backup set.

---
<!-- COMMENTS:END -->
