---
id: TASK-98
title: Cancel orders and bookings through one Cancel change
status: in-progress
assignee: []
created_date: '2026-10-22 19:47'
updated_date: '2026-10-22 19:48'
labels:
  - spec
  - developers
  - admin
dependencies: []
priority: medium
type: refactor
ordinal: 204000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cancelling an order or a course booking means the same thing everywhere, defined once in a shared Payments change.

**Why:** the cancel steps were copied into three actions and drifted: a booking can be cancelled twice, releasing an unpaid seat hold runs the refund and email steps for nothing, and a customer who cancels their subscription is emailed the shop's wording. The admin pages also do the refund arithmetic themselves, so retry safety lives in socket state where no domain test reaches it.

Decisions (architecture review, 2026-10-22):
- `Payments.Changes.Cancel, cancelled_by:` owns Cancelled for any payable: refuse unless committed and not already cancelled, set `cancelled_at`, close the open PaymentIntent, refund down to what's kept, queue the cancelled email. Each resource sets its own status and adds its own extras (stock).
- Cancel takes `refund` (what Jennie typed; left out = everything held) and `held` (amount held when the drawer opened). `kept_amount = held - refund`. Held now lower than `held` is a retry and goes ahead; higher means money arrived while the drawer was open, so it refuses.
- The Payable fragment requires `customer_email` and a `:cancel` action.
- Unpaid seat holds are released by their own `CourseRegistration :release_hold`.
- `Subscription :cancel` passes who cancelled to each occurrence's `Order :cancel` through a `cancelled_by` argument.
- One cancelled-email worker and one refunded-email worker; `Email` picks the template per resource. The BCC follows who cancelled: Jennie gets a record copy, a customer's cancel reaches her inbox.
- One shared Cancel test runs every case against an order and a booking.
<!-- SECTION:DESCRIPTION:END -->
