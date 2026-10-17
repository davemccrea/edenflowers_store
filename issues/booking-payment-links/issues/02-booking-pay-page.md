# The customer pays a booking's link on its own page

Status: ready-for-agent
Type: feature

## What to build

Spec decision 4.

- `/courses/pay/:token`, a LiveView in the courses feature, in the booking's locale: course, date, seats, paid, owed, and the Payment Element through `Payments.setup/2`. Paid, it shows that; an unknown token flashes and redirects home, as `PayLive` does.
- Subscribes to the booking's paid broadcast so the page updates when the webhook lands.
- New copy through gettext, with en, fi and sv msgstrs.

## Tests

- The page shows what's owed and never other bookings' details; an unknown token redirects.
- A settled booking's page says it's paid and offers no payment.
- Returning from Stripe with a succeeded redirect shows the paid state once the payment is recorded.

## Acceptance criteria

- [ ] Every case above passes
- [ ] The existing suite passes

## Blocked by

- 01
