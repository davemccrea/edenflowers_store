# Refund idempotency key is stable; partial Stripe failure in refund_balance

Status: ready-for-agent

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
