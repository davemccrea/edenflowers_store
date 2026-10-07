# Create and charge each delivery

Status: resolved

## Parent

`.scratch/subscriptions/spec.md`

## What to build

A scheduled job turns each active subscription into an ordinary placed Online Order a few days (`lead_days`, e.g. 3) before its next delivery date. That order is an **Occurrence**. The job charges the saved card off-session and records the Payment. From then on the order behaves like any other: it shows in fulfilment, sends the confirmation email, and counts in sales. Then the subscription moves on to its next date.

This slice covers the happy path only. A failed charge is slice 03.

## Acceptance criteria

- [x] Occurrences have a new order origin `:subscription` and link to their subscription; admin order views show a "Subscription" badge.
- [x] The line item comes from the variant at its **current** price through the normal add-to-cart path, so the free-delivery flag is copied over. The delivery fee is priced as for any order, so it's 0 inside the free zone.
- [x] Customer name and email are read from the user at creation time; recipient and delivery details come from the subscription.
- [x] If the delivery date is a closed day for the delivery option (`Fulfillment.Availability`), the date moves to the next open day.
- [x] Dates in `skipped_dates` create no order and just move the subscription on.
- [x] The off-session charge uses a deterministic idempotency key (subscription + date). Re-running the job never creates a second order or charge.
- [x] A failed HERE geocode or a Stripe network error leaves the job to retry. It does not cancel the subscription or advance its date.
- [x] Tests cover the happy path, a closed-day roll-forward, a skip, and an idempotent re-run (`Oban.Testing`).

## Blocked by

- `01-subscribe-at-checkout.md`

## Comments

**Built (slice 02)**

- `Subscription` gains AshOban and the `:create_occurrence` trigger (hourly; `state == :active and next_fulfillment_date <= today + 3`, `@lead_days 3`), running the update action `:create_occurrence` (`transaction? false`) with `Changes.CreateOccurrence`. The system actor may run it.
- `Changes.CreateOccurrence`: a skipped date just moves the date on (and drops it from `skipped_dates`). Otherwise it finds or makes the order for `(subscription, date)`, charges it, places it, and only then moves `next_fulfillment_date` on by one interval, counted from the scheduled date, not the rolled one.
- `Order :create_occurrence` makes the order in `:payment` state with `origin: :subscription`, `subscription_id` and new `subscription_date`. It runs `SnapshotFulfillmentMethod`, `SetGiftFromRecipient` and `PriceFulfillment`, then adds the line through `LineItem :add_to_cart`, so the current price and `free_delivery` are copied. Customer name and email come from the user at that moment. A closed day rolls forward to the first day where `Availability.unavailable_reason/3` is nil, searching up to 28 days.
- Placing reuses checkout: the PaymentIntent id is stored with `add_payment_intent_id`, then `Payments.complete/1` runs `finalize_checkout` (VAT snapshot, `RecordPayment :stripe`, confirmation email). The webhook and `reconcile_payment` can place it the same way. `ActivateSubscription` now runs only for `origin: :online`, so an Occurrence doesn't start a new subscription.
- `StripeAPI.charge_off_session/3` (amount, `%{customer, payment_method, metadata}`, idempotency key) uses `off_session` + `confirm` with key `"sub-#{id}-#{date}"`.
- Admin order list and order page show a "Subscription" badge (`subscription_badge` in admin components). Added sv/fi translations.
- Migration `add_subscription_occurrences`: `orders.subscription_date` plus a unique index on `(subscription_id, subscription_date)`.
- Tests: `test/edenflowers/orders/create_occurrence_test.exs` (9 tests): happy path through scheduler and worker, lead-time cutoff, closed-day roll-forward, skip, re-run after placed, after a HERE failure, after a Stripe network error (same key), after a not-yet-succeeded charge (retrieves, doesn't recharge), and a refused card. One more badge test in `orders_live_test.exs`.

**Decisions and deviations**

- Idempotency has three layers: the unique `(subscription_id, subscription_date)` order, the Stripe key, and the stored `payment_intent_id`. A retry with that id set asks Stripe (`retrieve_payment_intent`) instead of charging again, so a retry more than 24 hours later can't double-charge. The one gap left is a crash between Stripe answering and the id being stored, followed by a retry more than 24 hours later.
- The Occurrence waits in the existing `:payment` checkout state (added to `initial_states`) rather than a new state, so `finalize_checkout`, the webhook and reconcile place it with no new code. Like any cart, it can be read by anyone who knows its UUID until it is placed.
- Any failure after the charge (storing the PaymentIntent id or placing) is logged with `Logger.error` and fails the job. Nothing that was recorded is rolled back. The retry, webhook or reconcile records it later.
- A declined charge or `authentication_required` (`%Stripe.Error{code: :card_error}`) is logged as an error and fails the job. Nothing is placed or moved on. This is the one clause in `CreateOccurrence.charge/2` that slice 03 replaces (the comment marks it). Until then, the hourly scheduler re-enqueues it, but Stripe replays the cached decline for the same key, so the card isn't retried.
- Card: the Occurrence keeps `card_message` (and `gift` via `SetGiftFromRecipient`) but gets no card line item, because that was simpler. If the first order had a paid card, later deliveries don't charge for one.
- A HERE failure becomes a `PriceFulfillment` validation error, which fails the job, so it retries. An address that falls out of range also keeps retrying.
- `max_attempts 20` like the other triggers; the scheduler re-enqueues after discard anyway.

**Open questions**

- ~~If the job is down past a date, should a past date be skipped?~~ Resolved in review: a date already past with no order is dropped, logged as an error, and the subscription moves on. Nothing was charged for it.
- "today" in the trigger is the database's UTC date, not Helsinki's. With 3 lead days this doesn't matter.
