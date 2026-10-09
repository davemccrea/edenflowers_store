# Trim dead weight in the Stripe handler tests

Status: resolved

## Parent

`.scratch/test-suite-review/issues/01-review-test-suite.md` (deletions)

## What to build

- Merge the three `payment_intent.payment_failed` tests into one that asserts the order and the booking are unchanged.
- Cut the two trivially true "unhandled events" tests down to one.
- Drop the `Repo.delete_all(Oban.Job)` from setup, since the test is async and sandboxed.
- Make "refund of a payment the shop doesn't know is ignored" assert that no Payment was written.

## Acceptance criteria

- [ ] The items above are done
- [ ] The suite still passes

## Blocked by

None - can start immediately

## Comments

- The three `payment_intent.payment_failed` tests are now one, which checks that both the order and the course booking stay pending. Only the `invoice.paid` catch-all test remains under "unhandled events". `Repo.delete_all(Oban.Job)` is gone from setup.
- The unknown-payment refund test now checks that no Payment was written for the refund.
- The suite passes (987 tests).
