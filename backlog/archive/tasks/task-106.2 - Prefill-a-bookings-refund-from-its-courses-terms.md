---
id: TASK-106.2
title: Prefill a booking's refund from its course's terms
status: done
assignee: []
created_date: '2026-10-23 18:42'
updated_date: '2026-10-23 20:59'
labels: []
dependencies: []
parent_task_id: TASK-106
type: feature
ordinal: 228000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie shouldn't work out the refund by hand each time, but must still be able to be generous.

The cancel drawer for a booking prefills the refund: everything paid before the deadline, minus the fee after it. Jennie can change it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Before the deadline the drawer prefills a full refund
- [x] #2 After the deadline it prefills the price minus the fee
- [x] #3 Jennie can still change the amount
<!-- AC:END -->
