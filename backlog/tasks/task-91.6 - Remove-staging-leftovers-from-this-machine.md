---
id: TASK-91.6
title: Remove staging leftovers from this machine
status: done
assignee: []
created_date: '2026-10-22 09:54'
updated_date: '2026-10-23 11:24'
labels:
  - quick
dependencies:
  - TASK-91.5
parent_task_id: TASK-91
type: chore
ordinal: 195000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** A stale SSH alias and an old dump of test data are clutter that suggests staging still exists.

Remove the `edenflowers-staging` alias from `~/.ssh/config` and delete `tmp/staging-2026-10-19.dump` in the main checkout.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ~/.ssh/config has no edenflowers-staging alias
- [x] #2 tmp/ has no staging dumps
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Removed the edenflowers-staging alias from ~/.ssh/config and deleted tmp/staging-2026-10-19.dump on 2026-10-23.

Also removed the staging server's host key (204.168.169.79) from ~/.ssh/known_hosts.
<!-- SECTION:NOTES:END -->
