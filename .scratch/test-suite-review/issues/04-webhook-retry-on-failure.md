# Stripe webhook returns :error so Stripe retries when recording fails

Status: resolved

## Parent

`.scratch/test-suite-review/issues/01-review-test-suite.md` (finding 3, gaps 2 and 8)

## What to build

When the handler can't record a `payment_intent.succeeded`, `refund.*` or `setup_intent.succeeded` event, it must return `:error` so Stripe redelivers (ADR 0002). No test drives these paths, so flipping any of them to `:ok` passes the suite. Reuse the `CHECK (false)` constraint trick on `oban_jobs` already used in `payments_test`.

## Acceptance criteria

- [ ] `payment_intent.succeeded` returns `:error` when the order can't be updated, and a redelivery after the constraint is dropped places the order
- [ ] A refund event whose order update fails returns `:error`
- [ ] `setup_intent.succeeded` returns `:error` when saving the card fails for a reason other than a cancelled subscription
- [ ] Changing any of the three `:error` returns to `:ok` makes a test fail

## Blocked by

None - can start immediately

## Comments

- New sync `stripe_handler_retry_test.exs`: a CHECK (false) on `oban_jobs` makes `payment_intent.succeeded` return `:error`, and dropping it lets a redelivery place the order. The same trick on `payments` makes a succeeded refund return `:error`.
- `stripe_handler_test.exs`: `setup_intent.succeeded` for an unknown subscription returns `:error`.
- Mutations confirmed caught: each of the three `:error` returns in `StripeHandler` (card save, refund, `payment_update_failed`) flipped to `:ok` fails one test.
