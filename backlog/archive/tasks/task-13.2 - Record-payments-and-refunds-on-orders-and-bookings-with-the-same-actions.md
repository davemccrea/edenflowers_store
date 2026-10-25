---
id: TASK-13.2
title: Record payments and refunds on orders and bookings with the same actions
status: done
assignee: []
created_date: '2026-10-17 16:35'
updated_date: '2026-10-19 20:30'
labels: []
dependencies:
  - TASK-13.1
parent_task_id: TASK-13
type: refactor
ordinal: 36000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

Decision 3 of the spec: the actions that record money move into `Payable`.

- `record_payment` (arguments `amount`, `payment_method`) and `record_stripe_refund` (arguments `stripe_refund_id`, `amount`) defined once in the fragment, from the existing `RecordPayment`, `RefundCoveredOutsideStripe` and `CancelOpenPaymentIntent`.
- New validations in `Edenflowers.Payments.Validations`: the record is `committed?`, and the amount doesn't take the balance past zero. Error messages say what to do ("Lower the order or cancel it before refunding", "That's more than is owed").
- `CourseRegistration` loses `mark_paid`, `record_refund` and `Courses.Changes.CollectBalance`. `Order` loses its own `record_payment` and `record_stripe_refund`. The order action's `load(@admin_show_load)` goes; the order page reloads after recording, as it does after refunding.
- Code interfaces: `Orders.record_payment/3` stays; `Courses.record_registration_payment/3` replaces `mark_registration_paid` and `record_registration_refund`. `Payments.record_refund_against/3` calls the same action name on either parent.
- Policies: the admin may run `record_payment` on both; the system actor `record_stripe_refund` on both, as today.
- Callers: `courses_live.ex` (the at-the-course "Record payment" sends the balance as the amount; the refund form sends its amount), `seeds.exs`, every test using the removed actions.

### Tests

Added to the shared `payable_test.exs`, run for an order and a booking:

- A payment of the whole balance by each non-Stripe method settles it and records one `Payment` with that method and `paid_at`.
- A part-payment leaves the rest owed.
- A payment larger than the balance is refused, and nothing is recorded.
- `:stripe` is refused as a method.
- A payment on a cancelled record is refused.
- A payment on an uncommitted record (unplaced cart, pending booking) is refused.
- A refund of a negative balance, up to `outside_stripe_refund`, is recorded and settles it.
- A refund larger than what was paid outside Stripe is refused; one larger than what's owed back is refused.
- A refund on a settled record (goodwill, nothing owed back) is refused.
- A mistaken payment is corrected by recording the opposite amount.
- Recording cancels an open PaymentIntent.
- A Stripe refund webhook records once, even redelivered, and a refund beyond what was owed back is recorded anyway and leaves a balance to collect.
- Customers can't run either action; the admin and system actor can (`policies_test.exs`).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every case passes for both an order and a booking
- [x] #2 Marking a booking paid at the course is still one tap after picking the method
- [x] #3 `mark_paid`, `record_refund` and `CollectBalance` are gone, and no code records money on either resource except through these two actions and the Stripe completion actions
- [x] #4 Seeds run (`mix ecto.reset`)
- [x] #5 The existing suite passes
<!-- AC:END -->
