---
id: TASK-7.4
title: Adjust stock when a custom order is edited or cancelled
status: done
assignee: []
created_date: '2026-10-11 12:26'
updated_date: '2026-10-18 08:25'
labels: []
dependencies:
  - TASK-7.1
parent_task_id: TASK-7
type: feature
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

Keep the count right for everything Jennie does in the admin, using the shared stock change from issue 01.

Saving a Custom Order takes stock for its tracked lines. Cancelling an open order puts its tracked lines back. Editing an open order puts the old lines back, then takes the new ones: the same change run twice, not a calculated difference. None of these are ever blocked or logged, since Jennie knows the shelf better than the count does. The count still floors at 0. Occurrences never touch stock.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Saving a Custom Order lowers stock for its tracked lines, and is never blocked even when it exceeds the count (which floors at 0, with no error logged).
- [x] #2 Cancelling an open order (Online or Custom) puts its tracked lines back.
- [x] #3 Editing an open order nets out correctly: a removed line comes back, 1 → 3 takes 2 more, and a swapped variant moves stock between the two.
- [x] #4 Subscription Occurrences never change stock.
- [x] #5 Fulfilled orders can't be edited or cancelled, so their stock never moves (existing guard, covered by a test).
<!-- AC:END -->
