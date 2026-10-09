# /checkout/complete/:id with a failed redirect flashes and returns to checkout

Status: resolved

## Parent

`.scratch/test-suite-review/issues/01-review-test-suite.md` (gap 10)

## What to build

Test `CheckoutCompleteController` when Stripe redirects back with `redirect_status=failed`. That branch is untested.

## Acceptance criteria

- [ ] `redirect_status=failed` sets an error flash and redirects to `/checkout`
- [ ] The order stays in its payment state, not placed

## Blocked by

None - can start immediately

## Comments

The flash-and-redirect test already existed (`order_live_test.exs`, "goes back to checkout, keeping their cart, when a redirect payment fails"); it now also asserts the order is still in `:payment`.
Confirmed caught: making the `redirect_status=failed` clause unreachable sends the customer to `/order/:id` and fails the test.
