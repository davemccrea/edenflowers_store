---
id: TASK-13.1
title: Work out what's owed on orders and bookings the same way
status: done
assignee: []
created_date: '2026-10-17 16:35'
updated_date: '2026-10-19 20:30'
labels: []
dependencies: []
parent_task_id: TASK-13
type: refactor
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

Decisions 1, 2, 4 and 7 of the spec: the `Payable` fragment's calculations, on both resources. No actions move yet.

- `Edenflowers.Payments.Payable`, a `Spark.Dsl.Fragment` of `Ash.Resource`, with the `amount_paid` and `paid_outside_stripe` aggregates and the `balance`, `refunded?`, `settled?`, `outside_stripe_refund` and `stripe_refundable?` calculations. Its moduledoc names what the including resource must supply: `has_many :payments`, `total_due` and `committed?`.
- `Order` and `CourseRegistration` include it and drop their own copies. `Order` gets `total_due` (its `grand_total`, 0 once cancelled) and `committed?` (placed). `CourseRegistration` keeps its `total_due` and gets `committed?` (confirmed or cancelled).
- An order's `amount_paid` now defaults to 0. Readers that took nil as "never paid" check for a positive amount: `pay_live.ex` ("Paid so far"), `order_details.text.eex`, the dashboard's Unpaid badge, `RefundInFull`'s `|| Decimal.new(0)`.
- `Order.payable?` and `payment_status` rebuilt as in decision 4. `amount_mismatch?` deleted: `order_payment_badge` reads `settled?` (update its `doc:`), `ReportAmountMismatch` compares `amount_paid` with `grand_total`.
- CONTEXT.md as in decision 7.

### Tests

One shared test module, `test/edenflowers/payments/payable_test.exs`, runs every case against an order and a booking (`for parent <- [:order, :booking]` generating the tests), with a small builder per parent: committed, with a total, cancelled, and payments of a given method and amount. That is what keeps the two identical from now on.

- Unpaid: balance is the total, not settled, nothing to refund.
- Paid in full by Stripe, by cash, by a mix: balance 0, settled.
- Part-paid: balance is the rest, not settled.
- Cancelled, never paid: total due 0, balance 0, settled.
- Cancelled, paid €80 by card: balance −80, not settled, `stripe_refundable?`, `outside_stripe_refund` 0.
- Cancelled, paid €80 cash: balance −80, `outside_stripe_refund` 80, not `stripe_refundable?`.
- Cancelled, paid €50 card + €30 cash: balance −80, `outside_stripe_refund` 30, `stripe_refundable?`.
- Cancelled and refunded in full: balance 0, settled.
- Refunded in full without being cancelled: `refunded?`, settled, though balance reads the total.
- Lowered after payment (order edited down, seat removed): negative balance, refund limits as above.
- Not committed (unplaced cart, pending booking): `committed?` false.

Order-only, in the existing order tests:

- An order edited up after payment has a positive balance (a booking can't be raised).
- `payment_status` for each case above: Refunded, nil for cancelled-never-paid, Paid for cancelled-still-holding-money, Pending for part-paid.
- `payable?` is false once cancelled or refunded, and the payment link page asks for nothing then.
- Checkout's PaymentIntent amount and the payment link amount are unchanged (existing tests cover them; they must stay green).
- `ReportAmountMismatch` still logs a checkout paid at a different amount.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every case in the shared module passes for both an order and a booking
- [x] #2 Receipts, the VAT breakdown, sales figures and the customer's account page are unchanged
- [x] #3 Neither resource computes balance, settled or refund limits outside the fragment
- [x] #4 The existing suite passes
<!-- AC:END -->
