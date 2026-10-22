---
id: TASK-98.2
title: Cancel through one shared Cancel change that takes the refund
status: done
assignee: []
created_date: '2026-10-22 19:47'
updated_date: '2026-10-22 19:58'
labels: []
dependencies: []
parent_task_id: TASK-98
type: refactor
ordinal: 206000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** one definition of Cancelled for orders and bookings, with retry safety and the refund range checked where domain tests reach them.

`Payments.Changes.Cancel` used by Order :cancel, :cancel_by_customer and CourseRegistration :cancel. Arguments `refund` and `held` replace accepting `kept_amount`. Payable requires `customer_email`. Bookings get `cancelled_at`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A booking can't be cancelled twice
- [x] #2 A retry after a partial Stripe refund keeps the same amount
- [x] #3 Money arriving while the drawer was open refuses the cancel
- [x] #4 One shared test runs the cancel cases against an order and a booking
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The fragment also requires a cancellable? calculation: an order is cancellable only while placed and pending, which committed?/cancelled? can't say. Cancel absorbed RefundAllButKept and the SendCancelledEmail change.
<!-- SECTION:NOTES:END -->
