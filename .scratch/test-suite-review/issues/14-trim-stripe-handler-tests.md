# Trim dead weight in the Stripe handler tests

Status: ready-for-agent

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
