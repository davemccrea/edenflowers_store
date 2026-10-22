---
id: TASK-81.3
title: Rehearse restoring a database backup on staging
status: done
assignee: []
created_date: '2026-10-21 08:32'
updated_date: '2026-10-22 09:51'
labels:
  - wontfix
dependencies: []
parent_task_id: TASK-81
type: task
ordinal: 166000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** A backup that's never been restored isn't known to work, and the first real restore shouldn't happen during an outage.

On staging: `just db-backup staging`, deploy a newer release, then `just rollback staging v<previous> tmp/staging-v<previous>-....dump` and check the shop works on the old release. Use a staging dump: pg_restore --create recreates the database under the dump's own name, so a production dump would land as edenflowers_store_prod on staging. Also fetch one dump back from the Storage Box once TASK-81.2 is done, and check `pg_restore --list` reads it. Write down anything that surprised you on TASK-81.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `just rollback` has rolled staging back to an earlier release and its dump, and the shop works
- [ ] #2 A dump fetched from the Storage Box passes pg_restore --list
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-22 09:51

---

Staging is being removed, so there is nowhere to rehearse a rollback.

---
<!-- COMMENTS:END -->
