# Customers can read only Payments on their own orders

Status: ready-for-agent

## Parent

`.scratch/test-suite-review/issues/01-review-test-suite.md` (finding 5, gap 6)

## What to build

The Payment read policy is never tested. Changing it to `authorize_if always()` still passes the suite.

## Acceptance criteria

- [ ] Customer B reading Payments filtered by Customer A's order gets `[]`
- [ ] The owner sees their own Payments
- [ ] Changing the read policy to `authorize_if always()` makes a test fail

## Blocked by

None - can start immediately
