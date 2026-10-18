---
id: TASK-17
title: Share Stripe payment handling between orders and course bookings
status: done
assignee: []
created_date: '2026-10-18 03:08'
updated_date: '2026-10-18 12:28'
labels:
  - spec
  - developers
dependencies: []
priority: medium
type: refactor
ordinal: 47000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Orders and course bookings take Stripe payments through one shared set of actions, so payment changes are made once

**Why:** `Order` and `CourseRegistration` each keep their own copy of the Stripe plumbing, so every payment change (goodwill refunds, saved cards) has to be made twice.

### Problem

`Edenflowers.Payments.Payable` already shares the balance maths and Jennie's own payments (`record_payment`, `undo_payment`, `record_stripe_refund`). But `Order` and `CourseRegistration` each still define their own copy of the Stripe plumbing:

| Action | Order | CourseRegistration |
|---|---|---|
| `add_payment_intent_id` | + `Validations.Payable` | as is |
| `mark_payment_cancelled` | identical | identical |
| `record_link_payment` | clears the paid PaymentIntent, records the payment, resets `receipt_emailed_at`, `ReportUnexpectedPayment`, `ReactivateSubscription` | clears the paid PaymentIntent, records the payment, resets `confirmation_emailed_at` |
| `open_payment_link` | refuses cancelled | refuses unconfirmed |
| `reconcile_payment` | identical | identical |

On top of that come matching entries in each resource's system-actor policy bypass, and differently named code interfaces (`Orders.mark_payment_cancelled` vs `Courses.mark_registration_payment_cancelled`). That's why `Edenflowers.Payments` branches per resource in `add_payment_intent_id/3`, `cancel_payable/2`, `complete_payable/4`, `metadata_key/1` and `expected_amount/1`.

The pages show the same split: `EdenflowersWeb.Checkout.PayLive` (235 lines) and `EdenflowersWeb.Courses.CoursePayLive` (214 lines) are mostly the same page, as are the two receipt controllers.

Goodwill refunds (`TASK-14`) and saved cards will each touch this code on both resources again.

### Decisions

1. **The identical actions move into `Payable`**: `mark_payment_cancelled` and `reconcile_payment` (the resource-specific Oban triggers stay on each resource, since their `where` differs), plus the system-actor authorisation for them.
2. **`add_payment_intent_id` moves into `Payable`.** The order's extra `Validations.Payable` stays on `Order`, unless it reads as true for a booking too, in which case it moves.
3. **`record_link_payment` keeps one definition per resource but shares its core.** The "clear only the PaymentIntent that was paid" anonymous change becomes a named `Payments.Changes` module that both use. Each resource keeps its own reset and its follow-on changes.
   Rejected: one fragment action with per-resource hooks. Ash fragments don't compose changes onto one action cleanly, and a hook indirection would read worse than two short actions.
4. **`Payments` calls actions by name, not by resource.** Every payable's actions share names, so `cancel_payable/2`, `add_payment_intent_id/3` and the link-payment branch of `complete_payable/4` call `Ash.update(payable, :action, …)` directly. The per-resource clauses that remain are the genuinely different ones: finding the record from metadata, and placing an order (`finalize_checkout`) versus confirming a booking (`confirm_payment`).
5. **The payment-link pages share one component, and so do Jennie's payment controls in the admin (`TASK-17.3`).** The Stripe Elements mount, the "pay" handler's freshness checks, `sync_amount`, `maybe_flash_failed_payment` and the paid/settled states live once. Each LiveView keeps its own loading, summary and copy.

### Out of scope

- Making a course booking an Order. See `TASK-16`.
- Changing what any payment does. This is a refactor; the existing suite is the check.
<!-- SECTION:DESCRIPTION:END -->
