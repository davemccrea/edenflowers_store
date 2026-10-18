---
id: TASK-7.3
title: Payment step blocks lines over stock
status: done
assignee: []
created_date: '2026-10-11 12:26'
labels: []
dependencies:
  - TASK-7.1
parent_task_id: TASK-7
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

A cart can go over stock after it was filled, when someone else buys the last units. Before the customer is charged, the checkout payment step checks every line against the current stock. While any line is over, no PaymentIntent is created and the step says which line and how many are left. Lines are never changed or removed automatically; the customer fixes the cart and carries on.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 With a line over the current stock, clicking Pay charges nothing and names the line ("Only N left" / "Sold out").
- [x] #2 Once the customer fixes the line, payment goes ahead as normal.
- [x] #3 Cart lines are never changed or removed automatically.
- [x] #4 Carts with only untracked variants behave exactly as before.
- [x] #5 New strings are localised (en, fi, sv).
<!-- AC:END -->
