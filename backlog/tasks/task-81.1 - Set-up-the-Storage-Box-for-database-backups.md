---
id: TASK-81.1
title: Set up the Storage Box for database backups
status: ready-for-human
assignee: []
created_date: '2026-10-21 08:32'
labels: []
dependencies: []
parent_task_id: TASK-81
type: task
ordinal: 164000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The server needs somewhere to copy its dumps to, and only the Hetzner console can create the sub-account and turn on snapshots.

In the Hetzner console:
- Create a sub-account for these backups (e.g. uXXXXX-sub1) with SSH support on and access limited to its own directory.
- Turn on automatic snapshots, daily, keeping about 30.
- If the production server is also at Hetzner, check the box is in a different location.

Then record the sub-account username and hostname (uXXXXX-sub1.your-storagebox.de) on TASK-81.2, or in the Ansible vault (`just vault production`). Installing the server's SSH key on the box happens in TASK-81.2, once Ansible has generated it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A sub-account exists with SSH on and access limited to its own directory
- [ ] #2 Automatic daily snapshots keep about 30 days
- [ ] #3 The sub-account username and hostname are recorded where TASK-81.2 can use them
<!-- AC:END -->
