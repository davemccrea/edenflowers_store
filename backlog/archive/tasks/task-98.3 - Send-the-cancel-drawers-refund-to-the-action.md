---
id: TASK-98.3
title: Send the cancel drawer's refund to the action
status: done
assignee: []
created_date: '2026-10-22 19:47'
updated_date: '2026-10-22 19:58'
labels: []
dependencies: []
parent_task_id: TASK-98
type: refactor
ordinal: 207000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** the order page and courses page each turn the refund into a kept amount and keep the retry snapshot in socket state; the action now does both.

Both drawers submit `refund` and `held`; delete `PaymentActions.kept_amount/2`, the duplicated range error and the order page's reload-and-guess error branch.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Both pages pass refund and held straight to :cancel and show its error
- [x] #2 kept_amount/2 is gone
<!-- AC:END -->
