---
id: TASK-91.5
title: Destroy the staging server
status: done
assignee: []
created_date: '2026-10-22 09:54'
updated_date: '2026-10-23 11:30'
labels:
  - quick
dependencies:
  - TASK-91.1
  - TASK-91.2
  - TASK-91.3
  - TASK-91.4
parent_task_id: TASK-91
type: chore
ordinal: 194000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The server costs money every month and has to be patched while it exists.

Ansible no longer knows about staging (removed before the move into `infra/`). Destroy the server at the host, which takes its compose setup and `edenflowers_store_staging` database with it. Do this last, once nothing points at it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Ansible has no staging host
- [x] #2 The staging server is destroyed
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Server destroyed at Hetzner on 2026-10-23.
<!-- SECTION:NOTES:END -->
