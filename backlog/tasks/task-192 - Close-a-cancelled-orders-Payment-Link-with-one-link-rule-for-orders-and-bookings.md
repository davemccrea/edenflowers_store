---
id: TASK-192
title: >-
  Close a cancelled order's Payment Link, with one link rule for orders and
  bookings
status: needs-triage
assignee: []
created_date: '2026-11-12 06:22'
labels:
  - spec
  - customers
  - admin
dependencies: []
references:
  - docs/adr/0002-payments-are-records.md
  - docs/adr/0007-elixir-calculations-for-unqueried-money-booleans.md
  - lib/edenflowers/payments/payable.ex
  - lib/edenflowers/orders/order.ex
  - lib/edenflowers/courses/course_registration.ex
  - lib/edenflowers/payments/actions/prepare_link_payment.ex
  - lib/edenflowers_web/features/checkout/pay_live.ex
  - lib/edenflowers_web/features/courses/course_pay_live.ex
  - test/edenflowers_web/features/checkout/payment_link_states_test.exs
priority: high
type: bug
ordinal: 357000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A Payment Link takes no money once its order or booking is cancelled, because orders and bookings read one rule for when a link is open.

**Why:** The glossary says a link asks for nothing once the purchase is cancelled. A booking's link follows that; an order's does not, so a customer may be able to pay through the link of a cancelled order while the page tells them there is nothing to pay. The rule is written once per resource and again in each pay page, and the copies already disagree.

## Problem

- **`payment_link_open?` differs.** Order: `not is_nil(payment_link_token) and payable?` (`order.ex:1030`). Booking: the same plus `and status in [:pending, :confirmed]` (`course_registration.ex:324-326`). `payable?` is `balance > 0 and not refunded?` (`payable.ex:286`). The order only knows about cancellation in its page template (`pay_live.ex:55`).
- **Suspected bug, read from the code and not reproduced.** A cancelled order with an unpaid cancellation charge and a link token has `balance > 0`, so `payment_link_open?` is true. `PrepareLinkPayment.open/1` (`prepare_link_payment.ex:29`) would then accept a charge, and `PaymentLink.payment_form` (`orders/order/payment_link.ex:113`) may render the Stripe form under "nothing to pay". The existing "cancelling with money retained" test (`payment_link_states_test.exs`, around 277-296) seeds the charge as already paid, so it does not cover this.
- **`paid?` differs.** Order: `committed? and payment_status == :paid and not cancelled?` (`order.ex:936-943`). Booking: `status == :confirmed and not refunded? and balance <= 0` (`course_registration.ex:296`).
- **Page state is decided four times.** A `cond` over cancelled / refunded / paid / confirming / pay in each template (`pay_live.ex:54-91`, `course_pay_live.ex:56-87`) and again for each title (`pay_live.ex:207-213`, `course_pay_live.ex:167-180`). They differ: only the course page has a "link closed" branch; "confirming" checks `payment_link_open?` on the course page only; "Left to pay" shows on `amount_paid > 0 && open` for orders (`pay_live.ex:137`) and on `amount_held > 0 and not paid? and open` for bookings (`course_pay_live.ex:118-122`).

## What to build

Start with a failing test for the cancelled order with an unpaid charge and a link token. If it passes, the bug is not real: record that here and drop the priority to medium.

Then move `payment_link_open?` and `paid?` into the `Payable` fragment, built on `committed?` and `cancelled?`, which each resource already supplies. Add one calculation there for where a link stands (cancelled, refunded, paid, payable, closed). Both pay pages and `PrepareLinkPayment` read it. "Confirming" (the Stripe-return overlay) stays in the page: it is UI state.

ADR 0002 intends this. ADR 0007 applies: `payment_link_open?` is filtered on (`subscription.ex:578`), so it stays an expression; the new link-state calculation starts as an expression and is measured.

## Still to decide (grill before implementing)

- Should a cancelled order's unpaid cancellation charge be payable through its link at all? The glossary says cancelling leaves a Balance to collect "to settle with the customer". If Jennie should be able to send a link for it, the rule is not simply "cancelled closes the link", and the booking's rule is the one that changes.
- Which `paid?` definition is right for both, and which "Left to pay" condition.
- Whether `record_link_payment` and the `reconcile_payment` trigger's `where` (near-identical in both resources) move into `Payable` in the same task.
- Whether the fix for the bug ships first on its own and the unification follows as a second spec.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A test covers a cancelled order with an unpaid cancellation charge and a Payment Link: the link page shows no payment form and preparing a link payment is refused
- [ ] #2 payment_link_open? and paid? are defined once, in the Payable fragment, and Order and CourseRegistration no longer define their own
- [ ] #3 Both pay pages choose their heading, body and title from one link-state calculation instead of their own cond over raw fields
- [ ] #4 The link states (cancelled, refunded, paid, payable, closed) are tested at the resource for both orders and bookings; each pay page keeps only wiring tests
<!-- AC:END -->
