# A booking can open a payment link and record what's paid through it

Status: done
Type: feature

## What to build

Spec decisions 2 and 3, domain only.

- `payment_link_token`, `open_payment_link`, `payment_link_open?` and `by_payment_link_token` on `CourseRegistration`; generated migration. `OpenPaymentLink` moves to `Edenflowers.Payments.Changes`.
- `record_link_payment` on `CourseRegistration`, and the `Courses` code interface for it, `open_registration_payment_link` and `get_registration_by_payment_link_token`.
- `Payments.complete_payable/4` routes a confirmed booking's payment to `record_link_payment`; `expected_amount/1` uses a booking's balance when loaded.
- Policies: the admin opens a link; the system actor records a link payment and reads by token.

## Tests

- Opening a link on a confirmed booking owing money gives a token, and opening again keeps it; a cancelled or settled booking has no open link.
- A PaymentIntent for a booking with part paid is for the balance.
- A succeeded PaymentIntent on a confirmed booking records a Stripe payment and settles it; redelivered, it's recorded once; a pending booking's checkout still confirms through `confirm_payment`.
- Recording a payment by hand cancels the link's open PaymentIntent.

## Acceptance criteria

- [ ] Every case above passes
- [ ] The existing suite passes
