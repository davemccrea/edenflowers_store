# Subscribe at checkout and save the card

Status: resolved

## Parent

`.scratch/subscriptions/spec.md`

## What to build

A customer can put a florist's-choice subscription bouquet (S/M/L) in the cart, pick how often (every 1, 2 or 4 weeks), and check out for delivery as usual. Paying the first order saves the card in Stripe for later off-session charges. When the payment succeeds, the first order is placed as normal, and an active **Subscription** is created from it. Its next delivery date is the first order's date plus the interval. Jennie can see subscriptions in a simple admin list.

No later deliveries are created yet; that is slice 02.

Also record the new terms (**Subscription**, **Occurrence**) in `CONTEXT.md` and add ADR 0003, "Subscriptions create ordinary orders". The ADR should cover why the schedule lives here and not in Stripe Billing, with Stripe only holding the card.

## Acceptance criteria

- [ ] A product can be marked `subscribable`; a subscribable product must also be `free_delivery` (validation), so subscribers always get free delivery inside the free zone.
- [ ] Seeds add a "Seasonal bouquet subscription" product with S/M/L variants.
- [ ] A cart holding a subscribable variant shows a frequency choice and allows only that one line item (a card is fine if cards are already line items — decide and note it).
- [ ] Subscription carts allow delivery options only; pickup is rejected server-side, not just hidden.
- [ ] Subscription checkout requires an email so the order gets a user (existing upsert).
- [ ] The PaymentIntent for a subscription cart is created with a Stripe Customer and `setup_future_usage: "off_session"`; new `StripeApi` callbacks are covered by the existing test mock.
- [ ] On `finalize_checkout`, a Subscription is created: user, variant, interval, recipient and delivery snapshot, locale, card message, Stripe customer and payment method, `next_fulfillment_date`, and state `active`. The first order links to it.
- [ ] Redelivered webhooks don't create a second subscription.
- [ ] An admin page lists subscriptions: customer, size, interval, next date, state.
- [ ] Tests cover activation, pickup rejection, and idempotency.

## Blocked by

None - can start immediately

## Comments

**Built (slice 01)**

- `Product.subscribable`, with a validation that a subscribable product is also `free_delivery`. Checkbox on the admin product form. Seeds add a "Subscriptions" category with "Seasonal bouquet subscription" (S/M/L at 45/60/75).
- `LineItem.subscribable` is snapshotted by `PopulateFromVariant`, the same way as `free_delivery`. `Changes.KeepSubscriptionAlone` on `:add_to_cart` stops a subscription sharing the cart with any other non-card line, in either order, and stops it being added twice. `increment_quantity` keeps a subscription line at 1, and the cart hides its +/- buttons. The product page shows a flash when an add is refused.
- `Order.subscription?` (exists aggregate) and `Order.subscription_interval_weeks`. The delivery step shows a "How often" radio (every 1/2/4 weeks) and lists only delivery options for a subscription cart. `Validations.SubscriptionDelivery` on `submit_delivery` rejects pickup and a missing or invalid interval on the server. The step summary shows the interval. `ResetCheckout` clears the interval.
- `StripeAPI` behaviour gains `create_customer/1` and `create_payment_intent_saving_card/3` (`customer` + `setup_future_usage: "off_session"`, automatic payment methods). `Payments.setup` uses them for a subscription cart. `Payments.complete` passes the PaymentIntent's `customer`/`payment_method` into `finalize_checkout` as new optional arguments.
- `Edenflowers.Orders.Subscription` (AshStateMachine, AshPaperTrail): user, variant, fulfillment option, interval, `next_fulfillment_date`, `skipped_dates`, the recipient/delivery/card/locale snapshot, and the Stripe customer and payment method. `Order belongs_to :subscription`.
- `Changes.ActivateSubscription` in `finalize_checkout` creates it (`next_fulfillment_date` = first date + interval) and links the first order, inside the same transaction. A redelivered webhook is already stopped by the recorded-PaymentIntent check, so it can't start a second subscription.
- `/admin/subscriptions` (Cinder): customer, size, interval, next delivery, state. It is linked in the admin nav.
- CONTEXT.md now defines Subscription and Occurrence. Added ADR 0003.
- Tests: `test/edenflowers/orders/subscription_test.exs` (validation, cart rules, pickup and interval rejection, saving-card setup, activation, idempotency, no subscription for an ordinary order), `test/edenflowers_web/features/admin/subscriptions_live_test.exs`, and a delivery-step UI test in `checkout_delivery_live_test.exs`.

**Decisions and deviations**

- A card may go with a subscription, because cards are already line items and the gift step adds them. The subscription snapshots `card_message`. Whether occurrences carry a card line is left to slice 02.
- No `:pending` state. The interval sits on the order while checkout is unpaid, and the Subscription is created only once the order is paid, so it starts `:active`. States are `active`, plus `paused`, `payment_failed` and `cancelled` declared as `extra_states` for later slices. No transitions are defined yet.
- The email requirement was already met: every checkout's step 1 requires an email and upserts the user, so no change was needed.
- `charge_off_session/3` is not added yet. It belongs to slice 02.
- A new Stripe Customer is created per subscription checkout. Nothing reuses one per user yet.
- If creating the Subscription fails, `finalize_checkout` fails with it, so the order is not placed and the webhook or reconcile reports the error. This is strict on purpose.
- New `~t` strings are not yet extracted or translated into fi/sv (`mix gettext.extract --merge --sync`).
