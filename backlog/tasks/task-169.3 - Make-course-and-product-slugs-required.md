---
id: TASK-169.3
title: Make course and product slugs required
status: done
assignee: []
created_date: '2026-11-01 21:15'
updated_date: '2026-11-05 08:11'
labels: []
dependencies:
  - TASK-169.1
  - TASK-169.2
parent_task_id: TASK-169
type: chore
ordinal: 317000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Once production has backfilled slugs, the database should guarantee every course and product has one, and the UUID fallback code can go.

Ships as a second deploy after TASK-169.1 and TASK-169.2 are live and backfilled in production. Remove the Release.migrate backfill once it is no longer needed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 slug is allow_nil? false on Course and Product, with a generated migration
- [x] #2 The backfill step in Release.migrate is removed
<!-- AC:END -->
