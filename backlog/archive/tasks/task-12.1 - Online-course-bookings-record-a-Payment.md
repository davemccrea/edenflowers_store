---
id: TASK-12.1
title: Online course bookings record a Payment
status: done
assignee: []
created_date: '2026-10-17 09:39'
labels: []
dependencies: []
parent_task_id: TASK-12
type: refactor
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

The tracer bullet for the spec: the `payments` table takes course bookings, and a booking paid online records its money there (decisions 1 to 4, 6).

- Move `Edenflowers.Orders.Payment` to `Edenflowers.Payments.Payment` and make `Edenflowers.Payments` an Ash domain. Move `Orders.Order.PaymentMethod` with it. Update every caller (`RecordPayment`, `SalesSummary`, the admin order detail page, `Payments`).
- Add a nullable `course_registration_id`, make `order_id` nullable, and add a check constraint that exactly one is set. `CourseRegistration` gets `has_many :payments`.
- `confirm_payment` records a positive `:stripe` `Payment` with the `payment_intent_id`, `paid_at` and the card details from `Payments.paid_with/1`, instead of accepting `payment_method_type`, `card_brand` and `card_last4`.
- The course receipt (`Orders.Receipt`) reads the payment from the registration's `Payment` rows.
- Drop `payment_method_type`, `card_brand` and `card_last4` from the registration.
- A customer reads payments on their own orders and their own registrations.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A booking paid online has exactly one positive `:stripe` `Payment` with its `paid_at`, even with webhook redelivery or reconciliation
- [ ] #2 A `Payment` with both or neither parent is refused by the database
- [ ] #3 The course receipt shows the same payment details as before
- [ ] #4 Order payments and refunds behave exactly as before
<!-- AC:END -->
