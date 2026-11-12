---
id: TASK-192
title: Close a cancelled order's Payment Link
status: done
assignee: []
created_date: '2026-11-12 06:22'
updated_date: '2026-11-12 07:10'
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
A Payment Link takes no money once its order is cancelled.

**Why:** Confirmed by a failing test on 2026-11-12: a custom order that had a Payment Link and was then cancelled keeping an unpaid cancellation charge shows "Order cancelled, nothing to pay" with a working Stripe form for the charge beneath it, and preparing a link payment returns a client secret. The glossary says a link asks for nothing once the purchase is cancelled, and a cancelled booking's link already behaves that way.

## Problem

`Order.payment_link_open?` is `not is_nil(payment_link_token) and payable?` (`order.ex:1030`), with no cancelled check. `payable?` is `balance > 0 and not refunded?` (`payable.ex:286`), and an unpaid cancellation charge leaves a balance. Cancelling does not clear the token. Everything that reads the calculation is wrong for such an order: the pay page's form (`lib/edenflowers_web/payment_link.ex`), `PrepareLinkPayment.open/1`, the customer account's "pay now" (`order/customer.ex:68`) and the order details email.

Jennie cannot open a link on an already cancelled order (`order/admin.ex:669`), so only orders that had a link before cancelling are affected.

## Decisions (grilled 2026-11-12)

- Cancelling closes the link. Jennie collects an unpaid charge herself and records it by hand.
- A link payment that still succeeds on a cancelled order (the form was already open) is recorded as it is today, leaving Jennie a Balance to refund. `record_link_payment` gets no cancelled guard.
- `paid?` and the pay pages' "Left to pay" line stay as each resource has them.
- No link-state calculation and no rewrite of the pay pages: there is no known wrong case once the rule is fixed.
- `record_link_payment` and the `reconcile_payment` trigger stay where they are.

## What to build

Add the cancelled check to the order's `payment_link_open?`, with the failing test from the `repro-task-192` worktree. It stays an expression (ADR 0007: `subscription.ex:578` filters on it).

Only if `not cancelled?` gives the same answer as the booking's `status in [:pending, :confirmed]` for every booking status: define `payment_link_open?` once in the `Payable` fragment and delete both resources' copies. If they are not equivalent, leave the booking's as it is and say why in the notes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A test covers a custom order with a Payment Link, cancelled keeping an unpaid cancellation charge: the link page shows no payment form and preparing a link payment is refused with :link_closed
- [x] #2 The customer's account no longer offers pay now for that order
- [x] #3 payment_link_open? is defined once in Payable if the order and booking rules are equivalent; otherwise the notes say why the booking keeps its own
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
payment_link_open? now lives once in Payable (not is_nil(payment_link_token) and payable? and not cancelled?); a booking's only statuses are pending, confirmed and cancelled, so the booking's rule is unchanged. The admin order page also hides Get payment link on a cancelled order. Not checked: Stripe test mode in a browser, and whether production holds a cancelled order with an open link and an unpaid charge.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-12 06:38

---

Grilled with David on 2026-11-12, then cut down after a Ponytail review of the plan: the one-line fix ships on its own; the link-state calculation and pay page rewrite were dropped for lack of a wrong case. Not checked: whether production already holds a cancelled order with an open link and an unpaid charge.

---
<!-- COMMENTS:END -->
