---
id: TASK-91.4
title: Remove staging's Brevo key and sender
status: done
assignee: []
created_date: '2026-10-22 09:54'
updated_date: '2026-10-23 11:24'
labels:
  - quick
dependencies: []
parent_task_id: TASK-91
type: chore
ordinal: 193000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** A live API key for a dead server is a secret nobody watches.

If staging had its own Brevo API key or sender, delete them. If it shared production's, do nothing.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No Brevo key or sender used only by staging is still active
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Staging shared production's Brevo setup and had no key or sender of its own, so nothing to delete (confirmed 2026-10-23).
<!-- SECTION:NOTES:END -->
