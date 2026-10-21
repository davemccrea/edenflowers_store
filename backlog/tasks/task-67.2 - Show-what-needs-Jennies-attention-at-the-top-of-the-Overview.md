---
id: TASK-67.2
title: Show what needs Jennie's attention at the top of the Overview
status: done
assignee: []
created_date: '2026-10-20 06:52'
updated_date: '2026-10-21 21:07'
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

### What was built

A Needs attention strip at the top of the Overview, hidden when empty. One collapsed line per kind of problem with its count (and sum, for money), opening to rows that link to where she fixes each one:

- Overdue orders: placed, pending, fulfillment date before today. They left the Today section.
- Missing recipient phone on today's or tomorrow's deliveries.
- Subscriptions at `payment_failed` (`Orders.list_failed_subscriptions`).
- To refund: every negative balance, orders and bookings.
- Payment overdue: still owed 14 days after an order is fulfilled or a course is held (`payment_overdue?` on Order and CourseRegistration, the term in `Payment.overdue_after_days/0`).
- Sold out: sizes with `stock_quantity` 0 on a live product, cards included (`Catalog.list_sold_out_variants`).

### Decisions

- Refunds and overdue payments moved here from Open balances, which is now a To collect section for what's owed but not yet overdue. Customers pay after delivery, so most of what's owed isn't a problem.
- 14 days follows the usual Finnish invoice term.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each kind shows with the right count and link, and the strip is absent when all are zero
- [x] #2 Counts come from domain read actions
- [x] #3 The existing suite passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Remove the Overdue groups from the Today widget (the overdue: attr on day_widget) when the strip lands.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @codex
created: 2026-10-21 21:07

---

Commit 2e39dabd (2026-10-22): when the attention strip is empty, Overview now shows an all-clear status message: “Nothing needs attention right now.”

---
<!-- COMMENTS:END -->
