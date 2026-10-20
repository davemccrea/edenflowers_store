---
id: TASK-67.7
title: Compare this month's sales with the same point last month
status: ready-for-agent
assignee: []
created_date: '2026-10-20 06:52'
labels:
  - quick
dependencies: []
parent_task_id: TASK-67
type: feature
ordinal: 148000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** A month-to-date number means little on its own; against last month at the same day it tells Jennie whether things are up or down.

### What to build

- Under sales and revenue, last month's figures from its 1st to the same day of month (clamped to the month's last day), from `sales_summary`.
- Shown as the earlier figure, not a percentage.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Last month's figures cover the matching days, including at month ends
- [ ] #2 The existing suite passes
<!-- AC:END -->
