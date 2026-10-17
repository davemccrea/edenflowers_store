# Bookings paid at the course record a Payment, and registrations get a balance

Status: done
Type: feature

## What to build

Decisions 4 and 5 of the spec for money taken at the course.

- `mark_paid` takes a payment method, limited to `PaymentMethod.in_person/0`, and records a positive `Payment` for the booking's balance. Refused when nothing is owed.
- The admin course page asks for the method when Jennie marks a booking paid, as the order page does for an in-person payment.
- `CourseRegistration` gets `amount_paid` (sum of its payments) and `balance` (total due minus `amount_paid`; total due is 0 when cancelled, otherwise `amount / seats * seats_held`).
- `pays_at_course?` goes: the admin "still to pay" count and badge and the confirmation email use a positive balance on a confirmed booking instead.
- Drop `paid_at` from the registration.
- Copy through gettext; clear fuzzy msgstrs in en, fi and sv.

## Acceptance criteria

- [ ] Marking a booking paid records one positive `Payment` with the method Jennie picked
- [ ] A booking added manually and not yet paid shows as still to pay, and its confirmation email says to pay at the course
- [ ] `balance` is positive on an unpaid manual booking, zero once paid, and negative after `remove_seat` or `cancel` on a paid booking
- [ ] A pending online booking never paid isn't counted as still to pay

## Blocked by

01
