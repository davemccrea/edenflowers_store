---
id: TASK-91.5
title: Remove staging from phoenix-ansible and destroy the server
status: ready-for-human
assignee: []
created_date: '2026-10-22 09:54'
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

In phoenix-ansible, remove the staging host, its compose setup and the `edenflowers_store_staging` database. Then destroy the server at the host. Do this last, once nothing points at it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 phoenix-ansible has no staging host
- [ ] #2 The staging server is destroyed
<!-- AC:END -->
