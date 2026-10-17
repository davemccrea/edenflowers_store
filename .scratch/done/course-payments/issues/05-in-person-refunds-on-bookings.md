# In-person refunds on course bookings

Status: done
Type: feature

## What to build

Decision 4 of the spec for money handed back in person: a booking paid at the course is refunded in cash, MobilePay or on Zettle, and the Stripe refund button can't do that.

- A registration action records a negative in-person `Payment` with the method Jennie picks, on a confirmed or cancelled booking.
- It can't take the booking's in-person total below zero, the same rule as issue 04 for orders.
- The admin course page offers it on a booking that still holds in-person money and has a negative balance.
- Copy through gettext; clear fuzzy msgstrs in en, fi and sv.

## Acceptance criteria

- [ ] Jennie can record an in-person refund on a booking, including a cancelled one
- [ ] A refund larger than the in-person money taken is refused
- [ ] The booking's balance reaches zero once the refund is recorded

## Blocked by

02
