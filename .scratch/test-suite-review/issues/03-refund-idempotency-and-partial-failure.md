# Refund idempotency key is stable; partial Stripe failure in refund_balance

Status: resolved

## Parent

`.scratch/test-suite-review/issues/01-review-test-suite.md` (finding 2, gaps 5 and 9)

## What to build

The idempotency key is the only thing that stops two "Refund with Stripe" clicks from refunding twice. The `create_refund` mock ignores the key, so swapping it for a random value goes unnoticed. Pin the key in the mock, and cover a Stripe error partway through a multi-payment refund.

## Acceptance criteria

- [ ] The mock matches the key (`refund-<order id>-<n>-<payment intent>`) instead of ignoring it
- [ ] Two `refund_balance/1` calls made before any refund is recorded send the same key
- [ ] When `create_refund` errors on the second payment, the first refund is still recorded and the error is reported
- [ ] Replacing the key with `System.unique_integer()` makes a test fail

## Blocked by

None - can start immediately

## Comments

- The `create_refund` mock in the "newest payment first" test now asserts the key `refund-<order id>-2-<payment intent>`. New tests in `order_detail_live_test.exs`: two `refund_balance/1` calls with Stripe not yet listing the first (pending) refund send the same key; a `create_refund` error on the second payment keeps the first refund in the order log and flashes the error.
- Mutations confirmed caught: key replaced with `System.unique_integer()` (2 tests fail); dropping `record_refund/1` from `refund_from/4` (partial-failure test fails).
- No app-code bug: `refund_from/4` already records each refund before moving to the next payment.
