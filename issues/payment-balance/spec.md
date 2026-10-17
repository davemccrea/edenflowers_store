# Payment Balance

Status: ready-for-agent

## Problem

Orders and course bookings both record money as `Payment` rows (ADR 0002) and both have a `balance`, but it means different things:

- A booking's `total_due` is 0 once it's cancelled, so `balance = total_due - amount_paid` turns negative and reads "To refund" (`course_registration.ex:287`).
- An order's `balance` is `grand_total - amount_paid` whatever its status (`order.ex:1100`). Jennie's `cancel` refunds nothing, so a cancelled order paid by card reads €0, as settled, and a cancelled unpaid one still reads as owed.

The order code corrects for this in each place that reads `balance`: the cancelled branch of `payment_status`, `payable?`, `owes_money?` and `refundable_outside_stripe?` on the order page, and `order_payment_badge`, which goes through the single-payment-era `amount_mismatch?`. One gap remains: a cancelled order paid through Stripe gets no "Refund with Stripe" button, because the button needs a negative balance. Jennie has to refund it in the Stripe dashboard. A cancelled booking gets the button.

There is also no single place to see what's owed either way. Order balances show on each order and as badges on open orders, booking balances on the courses page. A fulfilled order still unpaid, or a cancelled one still holding money, shows nowhere Jennie looks each day.

## Decisions

1. **An order gets `total_due`, as a booking has: its `grand_total`, or 0 once cancelled. `balance` is `total_due - amount_paid`.**
   As on Shopify (total outstanding) and Magento (total due), the order's total is history and stays as ordered; what's owed is derived from it. `grand_total` keeps feeding receipts, the order page and the VAT breakdown. Only cancelled goes to 0, not unplaced: checkout prices its PaymentIntent from `balance` when loaded (`Payments.expected_amount/1`), so a cart's balance must stay its total.

2. **What reads `balance` stops special-casing cancelled orders.**
   - `payable?`: `balance > 0 and payment_status != :refunded`. The refunded clause stays: an order refunded in Stripe without being cancelled is settled though its balance reads as owed again.
   - `payment_status`: `:refunded` when positive payments were all handed back; `nil` when cancelled and nothing was ever paid; otherwise `:paid` when `balance <= 0` and `:pending` when not. A cancelled order still holding money reads `:paid` with "To refund", as today.
   - The order page shows the collect panel whenever `balance != 0`. A cancelled order paid through Stripe then gets "Refund with Stripe" from the existing panel. No new cancel dialog.
   - Refunding outside Stripe is the same panel as for any negative balance, prefilled with what was paid outside Stripe, as the courses page does (`outside_stripe_refund/1`). The separate `refund_outside_stripe` section goes.
   - `order_payment_badge` reads `balance != 0` instead of `amount_mismatch?`. `amount_mismatch?` is deleted; `ReportAmountMismatch` compares `amount_paid` with `grand_total` itself.

3. **The Overview shows one "To collect / To refund" widget for orders and bookings together.**
   In the right-hand column under "This month", hidden when nothing is owed. Two groups, To collect and To refund, each with a count and a sum, then one row per record: who, whether it's an order or which course, the amount, linking to the order page or the course on the courses page. Orders: placed, and `payable?` or `balance < 0`. Bookings: confirmed or cancelled, and `balance != 0`. Pending bookings are holds, not owed money, so they stay out. Both lists are read actions in their domains; the LiveView only merges and groups.
   It refreshes on the `admin:orders` broadcast the Overview already subscribes to. Booking changes don't broadcast there, so a booking settles on the Overview at the next page load; accepted.

4. **CONTEXT.md says it once.**
   **Balance**: "A cancelled order's or booking's total due is zero." Add **Total due**: what a placed order or confirmed booking is still to be paid for, before what's been paid is taken off; zero once cancelled. _Avoid_: amount due, outstanding.

## Out of scope

- A full payments ledger page. The monthly report's income sheet is that ledger.
- Refunding at cancel time. The panel offers it right after.
- Booking broadcasts to the Overview.
