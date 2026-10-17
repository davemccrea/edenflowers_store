# Refund course bookings from the app

Status: done
Type: feature

## What to build

Decision 7 of the spec: a button on the admin course page that refunds a booking's negative balance through Stripe, as Jennie already can for an order.

- Generalise `Payments.refund_balance/1` to take a registration as well as an order. It already refunds newest Stripe payment first, only as far as Stripe payments cover the balance, records refunds that succeed at once, and takes pending refunds off what's owed so a second click never refunds twice. Keep all of that.
- The button shows on a booking with a negative balance that its Stripe payments can cover. Money taken in person is refunded in person (issue 05).
- Cancelling or removing a seat still refunds nothing on its own.
- Copy through gettext; clear fuzzy msgstrs in en, fi and sv.

## Acceptance criteria

- [ ] Refunding a cancelled online booking refunds what was paid and records one negative `Payment`
- [ ] Refunding after `remove_seat` refunds one seat's price
- [ ] Two clicks never refund the same money twice
- [ ] Order refunds behave exactly as before

## Blocked by

02, 03
