# Customers can read only Payments on their own orders

Status: resolved

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

## Comments

- Added a "Payment reads" describe to `policies_test.exs`. The owner reads their order's Payment, and a second signed-in customer filtering by that `order_id` gets `[]`. The policy was already correct, so nothing changed in it.
- Confirmed: changing the read policy to `authorize_if always()` fails "another customer sees none of them".
