---
id: TASK-12.3
title: Record Stripe refunds on course bookings
status: done
assignee: []
created_date: '2026-10-17 09:39'
updated_date: '2026-10-18 07:27'
labels: []
dependencies:
  - TASK-12.1
parent_task_id: TASK-12
type: bug
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

Decision 4 of the spec for Stripe refunds. Jennie refunds course bookings in the Stripe dashboard today and nothing is recorded.

- `Payments.record_refund/1` finds the `Payment` by `payment_intent_id` and records the refund as a negative `:stripe` row with its `stripe_refund_id` against that payment's parent, order or registration. It no longer ignores course bookings.
- `Payments.sync_refunds/1` works for a registration too, so a refund whose webhook never arrived can be picked up.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A Stripe refund on a booking is recorded once as a negative `Payment`, even with webhook redelivery
- [ ] #2 A partial refund records only the refunded amount
- [ ] #3 Order refunds behave exactly as before
<!-- AC:END -->
