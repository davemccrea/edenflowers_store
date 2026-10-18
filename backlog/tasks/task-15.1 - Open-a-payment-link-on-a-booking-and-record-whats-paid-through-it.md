---
id: TASK-15.1
title: Open a payment link on a booking and record what's paid through it
status: done
assignee: []
created_date: '2026-10-17 18:41'
updated_date: '2026-10-18 07:27'
labels: []
dependencies: []
parent_task_id: TASK-15
type: feature
ordinal: 43000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

Spec decisions 2 and 3, domain only.

- `payment_link_token`, `open_payment_link`, `payment_link_open?` and `by_payment_link_token` on `CourseRegistration`; generated migration. `OpenPaymentLink` moves to `Edenflowers.Payments.Changes`.
- `record_link_payment` on `CourseRegistration`, and the `Courses` code interface for it, `open_registration_payment_link` and `get_registration_by_payment_link_token`.
- `Payments.complete_payable/4` routes a confirmed booking's payment to `record_link_payment`; `expected_amount/1` uses a booking's balance when loaded.
- Policies: the admin opens a link; the system actor records a link payment and reads by token.

### Tests

- Opening a link on a confirmed booking owing money gives a token, and opening again keeps it; a cancelled or settled booking has no open link.
- A PaymentIntent for a booking with part paid is for the balance.
- A succeeded PaymentIntent on a confirmed booking records a Stripe payment and settles it; redelivered, it's recorded once; a pending booking's checkout still confirms through `confirm_payment`.
- Recording a payment by hand cancels the link's open PaymentIntent.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every case above passes
- [ ] #2 The existing suite passes
<!-- AC:END -->
