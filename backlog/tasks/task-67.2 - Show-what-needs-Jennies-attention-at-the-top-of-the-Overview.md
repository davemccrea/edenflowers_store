---
id: TASK-67.2
title: Show what needs Jennie's attention at the top of the Overview
status: ready-for-agent
assignee: []
created_date: '2026-10-20 06:52'
updated_date: '2026-10-20 06:57'
labels: []
dependencies:
  - TASK-67.1
parent_task_id: TASK-67
type: feature
ordinal: 143000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Problems that block an order or lose a sale are easy to miss while they sit in separate lists.

### What to build

A strip at the top, hidden when empty, with one line per kind of problem: its count and a link to where she fixes it.

- Overdue orders: placed, pending, fulfillment date before today.
- Subscriptions at `payment_failed`: no occurrence is made until she acts.
- Sold-out sizes: `stock_quantity` 0 on a live product.
- Orders for today or tomorrow missing the recipient's phone.

Each count comes from a domain read action; no filtering in the LiveView. Refreshes on the existing `admin:orders` broadcast.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each kind shows with the right count and link, and the strip is absent when all are zero
- [ ] #2 Counts come from domain read actions
- [ ] #3 The existing suite passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Remove the Overdue groups from the Today widget (the overdue: attr on day_widget) when the strip lands.
<!-- SECTION:NOTES:END -->
