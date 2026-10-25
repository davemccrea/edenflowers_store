---
id: TASK-12
title: 'Record course booking money as Payments, as orders do'
status: done
assignee: []
created_date: '2026-10-17 09:39'
updated_date: '2026-10-20 12:33'
labels:
  - spec
  - admin
dependencies: []
priority: high
type: feature
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

ADR 0002 made every payment and refund on an order a `Payment` row, but course bookings never followed. Their money is fields on the registration (`amount`, `payment_intent_id`, `card_*`, `payment_method_type`, `paid_at`), so:

- **Online bookings don't record when they were paid.** `confirm_payment` sets `confirmed_at` but not `paid_at`.
- **Bookings paid at the course don't record how.** `mark_paid` only stamps `paid_at`.
- **Course refunds aren't recorded anywhere.** `Payments.record_refund/1` deliberately ignores course bookings, and cash handed back has nowhere to go.
- **In-person refunds on cancelled orders are refused.** `record_in_person_payment` rejects cancelled orders, so cash, MobilePay or Zettle handed back for one can't be recorded.

The monthly report (`TASK-11`) books sales from payments, so every payment and every refund must be recorded, in one place.

### Decisions

1. **One `payments` table holds every payment and refund: payments positive, refunds negative.**
   Stripe and in-person, orders and course bookings alike. Only money that moved is a row; a PaymentIntent still waiting for the customer stays on the order or registration as `payment_intent_id`.

2. **A Payment belongs to exactly one order or one course registration.**
   Two nullable foreign keys, `order_id` and `course_registration_id`, with a check constraint that exactly one is set. Chosen over a polymorphic `payable_type`/`payable_id`, which the database can't enforce and Ash handles awkwardly.

3. **The resource moves to `Edenflowers.Payments.Payment`, and `Edenflowers.Payments` becomes an Ash domain.**
   Its moduledoc already says it takes Stripe payments for orders and course bookings. Its existing functions stay on the module. `Orders.Order.PaymentMethod` moves with it, as both parents use it. The table keeps its name.

4. **Every way money moves on a booking is a row.**
   - Paid online: `confirm_payment` records a positive `:stripe` row with the `payment_intent_id`, `paid_at` and card details.
   - Paid at the course: `mark_paid` records a positive row with the in-person method Jennie picks (Zettle, MobilePay, cash, Zervant).
   - Stripe refund: the refund webhook records a negative row against whichever parent holds the PaymentIntent.
   - In-person refund: Jennie records a negative in-person row, also on a cancelled booking, never more than was taken in person.
   The unique `payment_intent_id` and `stripe_refund_id` stop Stripe's at-least-once delivery from counting money twice, for both parents.

5. **A registration has `amount_paid` and `balance`, as an order does.**
   Total due is 0 when cancelled, otherwise `amount / seats * seats_held`; `amount` is `price * seats`, so this is exact. Balance is total due minus `amount_paid`: positive is to collect, negative is to refund. A positive balance on a confirmed booking replaces `pays_at_course?`. A pending online booking never paid holds no money and is never shown as owing.

6. **`amount` and `seats` stay what was bought.**
   The receipt is rebuilt from them and is unchanged; it reads how it was paid from the `Payment` row instead of the registration.

7. **Nothing refunds on its own.**
   `cancel` and `remove_seat` leave a negative balance, as cancelling an order does. Jennie refunds it with a button that refunds through Stripe, as for an order, or records an in-person refund. Customers don't cancel their own bookings.

8. **No backfill.**
   Courses aren't in production. The registration's `paid_at`, `card_brand`, `card_last4` and `payment_method_type` are dropped.

Schema changes come from `mix ash.codegen`; never hand-write migrations. ADR 0002's amendment and `CONTEXT.md`'s **Payment** and **Balance** entries already describe the result.

### Out of scope

- Customers cancelling their own course bookings.
- Cancelling or removing a seat refunding anything automatically.
<!-- SECTION:DESCRIPTION:END -->
