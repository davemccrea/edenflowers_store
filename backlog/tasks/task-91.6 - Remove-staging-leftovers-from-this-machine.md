---
id: TASK-91.6
title: Remove staging leftovers from this machine
status: ready-for-human
assignee: []
created_date: '2026-10-22 09:54'
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
- [ ] #1 ~/.ssh/config has no edenflowers-staging alias
- [ ] #2 tmp/ has no staging dumps
<!-- AC:END -->
