---
id: TASK-92.2
title: 'Cancel an order from the admin with a refund, reason and email'
status: ready-for-agent
assignee: []
created_date: '2026-10-22 14:39'
labels: []
dependencies: []
parent_task_id: TASK-92
type: feature
ordinal: 198000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The order half of TASK-92: Jennie cancels, refunds and tells the customer in one step instead of three.

- `kept_amount` moves from `CourseRegistration` into `Payments.Payable`; a cancelled record's `total_due` is `kept_amount` (bookings already behave this way).
- `Order.cancel` takes `refund_amount`, `cancellation_reason` and `email_customer?`. Sets `kept_amount = amount_held - refund_amount`, refunds `amount_held - kept_amount` through Stripe before the transaction (generalise `RefundInFull`), and queues `SendCancelledEmail` when ticked and there is an address.
- `order_cancelled` email gains the reason paragraph and an "I'll return €Y" line for money held outside Stripe.
- `cancel_by_customer` keeps working unchanged.
- Delete `set_refund` and its UI; drop `not cancelled?` from `goodwill_refundable?`.
- Order page: Cancel opens a drawer (TASK-79 pattern) with the amount, reason and checkbox. History shows the reason and whether the customer was emailed.
- Remove the stale "Never refunds" comment on `cancel`. Update `CONTEXT.md`. Copy through gettext; clear fuzzy msgstrs in en, fi and sv.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Cancelling with a partial refund refunds that much through Stripe, keeps the rest and leaves a 0 balance
- [ ] #2 A refused Stripe refund leaves the order uncancelled and queues no email
- [ ] #3 Retrying a cancel never refunds twice
- [ ] #4 The email includes the reason and what was refunded or will be returned; none is sent when unticked or without an address
- [ ] #5 Goodwill refunds work on a cancelled order with money kept
- [ ] #6 The history shows the reason and whether the customer was emailed
<!-- AC:END -->
