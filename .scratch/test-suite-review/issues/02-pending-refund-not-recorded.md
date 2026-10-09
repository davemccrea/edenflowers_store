# A pending refund is recorded only once it succeeds

Status: resolved

## Parent

`.scratch/test-suite-review/issues/01-review-test-suite.md` (finding 1, gap 1)

## What to build

When a Stripe refund webhook arrives with `pending` status, nothing is written. A negative Payment appears only on `succeeded`. If a pending refund later fails or is cancelled, no Payment is ever written and the order's Balance stays the same. Today's test only checks the final row count, so it still passes when the `status: "succeeded"` guard in `record_refund` is removed.

## Acceptance criteria

- [ ] After a pending `refund.created`, the test asserts that no refund Payment exists
- [ ] New test: pending `refund.created`, then failed `refund.updated`, records nothing and leaves the Balance unchanged
- [ ] Removing the succeeded guard in `record_refund` makes a test fail

## Blocked by

None - can start immediately

## Comments

- The existing refund test now asserts that no refund Payment exists after the pending `refund.created`.
- New test: a pending refund followed by a failed `refund.updated` records nothing and leaves the Balance unchanged.
- Mutation confirmed caught: removing `status: "succeeded"` from `record_refund/1` fails both tests.
