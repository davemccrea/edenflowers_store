---
id: TASK-81
title: Keep an off-site copy of the production database backups
status: ready-for-agent
assignee: []
created_date: '2026-10-21 08:32'
updated_date: '2026-10-21 08:44'
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
Every nightly production database dump is copied to the Hetzner Storage Box, with about 30 days of history that survives a lost or compromised server.

**Why:** The only backups are the nightly pg_dump files in /opt/edenflowers_store/backups/ on the production server itself, so losing that server loses every order, customer and payment record along with its backups.

Decisions:
- rsync, not restic. Each dump is already a complete, dated, compressed file, so restic's snapshots and dedup add little. Restoring is copying a file back. The one thing restic would add is encryption at rest. Revisit if the box gets used for other things or that matters for GDPR.
- The server mirrors its backup folder, which the nightly cron already prunes to 30 days, to the box with `rsync -a --delete`. The Storage Box's automatic snapshots keep that history safe: they are managed in the Hetzner console, not over SSH, so a compromised server that wipes the mirror can't delete them.
- A dedicated Storage Box sub-account, so the server's key can only reach its own folder.
- Production only. Staging holds test data.
- Server work lives in phoenix-ansible (roles/common/tasks/backups.yml), next to the existing 02:00 pg_dump cron.

Related, already in this repo: `just db-backup production` (dump to tmp/, named after the running release), `just rollback <target> <tag> [dump]`, and the CLAUDE.md rule to back up before touching production.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A dump from the latest night is on the Storage Box
- [ ] #2 Storage Box snapshots give roughly 30 days of history
- [ ] #3 A missed or failed nightly copy sends an alert
<!-- AC:END -->
