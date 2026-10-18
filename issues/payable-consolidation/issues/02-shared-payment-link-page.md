# Share the payment-link page between orders and bookings

Status: ready-for-agent
Type: refactor
Blocked by: 01

## What to build

Spec decision 5.

- A component (or function components plus a small helper module) holding the Stripe Elements mount, the `pay` handler's freshness checks, `sync_amount`, `maybe_flash_failed_payment` and the paid, settled and cancelled states.
- `PayLive` and `CoursePayLive` keep their own mount (token lookup, locale, PubSub topic), summary and copy, and delegate the rest.
- Consider whether `ReceiptController` and `CourseReceiptController` can become one controller, since `Receipt.generate/1` already takes either record. Do it only if the routes stay as they are.

## Tests

- The existing LiveView tests for both pages pass unchanged.

## Acceptance criteria

- [ ] The payment flow code exists once
- [ ] The existing suite passes

## Comments
