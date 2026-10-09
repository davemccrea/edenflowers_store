# Move the shared fixtures into generators

Status: ready-for-agent

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
