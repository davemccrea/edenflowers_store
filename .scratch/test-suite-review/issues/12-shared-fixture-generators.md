# Move the shared fixtures into generators

Status: resolved

## Parent

`.scratch/test-suite-review/issues/01-review-test-suite.md` (finding 11)

## What to build

Add `placed_order` (with `paid:` and `refunded:` options), `subscription` and `order_in_payment` to the test generator. Replace the copied helpers with them: the per-file `placed_order`/`order_for` helpers in six admin and account LiveView tests, the copied `Ash.Seed.seed!(Subscription, …)` blocks, and the order-in-payment setup in the payments, reconcile and Stripe handler tests.

## Acceptance criteria

- [ ] No test file defines its own placed-order or subscription seeding helper
- [ ] The tests read just as clearly on their own
- [ ] The suite still passes

## Blocked by

None - can start immediately

## Comments

- `Generator.placed_order/1` builds Ada Lovelace's 88.50 pickup order, unpaid unless `paid: true` / `paid: "40.00"` / `refunded: true`; the six admin and account LiveView tests use it instead of their own helpers.
- `Generator.subscription/1` replaces every copied `Ash.Seed.seed!(Subscription, …)`. The change, manage and create-occurrence tests keep a small `subscription_for(context, …)` that only passes their setup's customer, variant and fulfillment option (create-occurrence also its gift recipient details).
- `Generator.order_in_payment/1` replaces the John Smith order + line item + PaymentIntent setup in the payments, reconcile and both Stripe handler tests.
- `order_for/1` in `account_live_test.exs` stays: it builds an unsaved map for `status_label/2`, not a seeded order.
