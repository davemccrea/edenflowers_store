---
id: TASK-200
title: Link a Stripe app payment to an order or course booking
status: ready-for-human
assignee: []
created_date: '2026-11-21 13:41'
updated_date: '2026-11-21 14:52'
labels:
  - spec
  - admin
dependencies: []
references:
  - lib/edenflowers/payments.ex
  - lib/edenflowers/payments/payable.ex
  - lib/edenflowers_web/webhooks/stripe_handler.ex
  - lib/edenflowers_web/features/admin/payment_actions.ex
priority: medium
type: feature
ordinal: 365000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie can link a card payment she took in the Stripe app on her phone to the order or course booking it pays for, and the shop then treats it as a Stripe payment.

**Why:** Jennie takes payments in the Stripe app, but admin can't mark an order paid that way. Recording it as a manual payment would leave the shop unaware that the money is in Stripe: refunds from admin wouldn't work, receipts wouldn't show the card, and the monthly report would label the sale as a manual payment while Stripe's fees-and-payouts sheet counts it.

## Today

A Stripe app payment sends `payment_intent.succeeded` without `order_id`/`course_registration_id` metadata. `Payments.complete/1` returns `:unknown_payable` and the webhook only logs it (`EdenflowersWeb.Webhooks.StripeHandler`). Refunds made in Stripe for it are ignored the same way (`Payments.record_stripe_refund/1`).

## What to build

- **Picker:** "Paid in the Stripe app" appears wherever "Record payment" does, for orders and course bookings. It lists successful PaymentIntents from the last 7 days that carry neither `order_id` nor `course_registration_id` metadata, newest first, showing amount, time and card ending.
- **Link:** a new action on `Edenflowers.Payments.Payable` writes the payable's metadata key onto the chosen PaymentIntent in Stripe, then records it through `record_link_payment`, the path an admin Payment Link already uses (placed orders, confirmed or cancelled bookings): a `:stripe` payment with `payment_intent_id` and `paid_with` card details.
- **Amount:** anything up to the balance can be linked, so a part payment leaves the rest owed. More than the balance is refused, and so is a PaymentIntent already linked to something.
- **Receipt:** an "Email receipt" checkbox, off by default, as on `record_payment`.
- **Unlink:** allowed only while the linked payment has no refunds. It records a reversal, as `undo_payment` does, so the history and any month already sent to the accountant stay intact. It also clears the metadata in Stripe, so the payment shows in the picker again and can be linked to the right order. Refunds from admin ignore a reversed PaymentIntent.

## Decisions

- Lookback 7 days; amount up to the balance; receipt optional; unlink by reversal (grilled with David on 2026-11-21).
- Out of scope: flagging Stripe app sales that never got an order. That stays a follow-up, like the Zettle gap noted in ADR 0004.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Order and course booking payment actions offer "Paid in the Stripe app" wherever "Record payment" is offered
- [x] #2 The picker lists only successful PaymentIntents from the last 7 days with no order_id or course_registration_id metadata, newest first, with amount, time and card ending
- [x] #3 Linking writes the payable's metadata onto the PaymentIntent in Stripe and records a :stripe payment with its payment_intent_id and card details
- [x] #4 Linking is refused for an amount over the balance and for a PaymentIntent already linked to something; a part payment leaves the rest owed
- [x] #5 An optional, off-by-default email receipt is sent when ticked
- [x] #6 A linked payment can be refunded from admin through Stripe like a checkout payment
- [x] #7 Unlinking is refused once the payment has refunds; otherwise it records a reversal, clears the metadata in Stripe, and the PaymentIntent can then be linked to another order or booking
- [x] #8 Admin refunds ignore an unlinked PaymentIntent
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Decision (2026-11-21): a PaymentIntent can only be recorded once (unique_payment_intent). To let an unlinked payment be linked again, unlinking also sets unlinked_at on the original Payment, and the identity becomes partial on unlinked_at IS NULL. The reversal row stays as history.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-21 14:52

---

Built and tested (mix precommit: 2465 tests, 0 failures). Left for a human: in live mode, take a small payment in the Stripe app, link it from an order's Record payment drawer (Stripe app), check the receipt shows the card, then unlink it with Undo and link it again. Not verified: the real shape of a Stripe app PaymentIntent (assumed succeeded, eur, no order_id/course_registration_id metadata, payment_method of type card_present).

---
<!-- COMMENTS:END -->
