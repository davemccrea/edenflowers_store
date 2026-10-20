---
id: TASK-13
title: Record and settle money on orders and course bookings the same way
status: done
assignee: []
created_date: '2026-10-17 16:08'
updated_date: '2026-10-20 12:33'
labels:
  - spec
  - admin
  - developers
dependencies: []
priority: medium
type: refactor
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Record and settle money on orders and course bookings the same way, and show what's owed in one place

### Problem

Orders and course bookings both keep their money as `Payment` rows (ADR 0002), but everything built on those rows was written twice, at different times, and came out different:

| | Orders | Bookings |
|---|---|---|
| What's owed | `balance` from `grand_total`, whatever the status | `balance` from `total_due`, 0 once cancelled |
| Money taken outside Stripe | `record_payment`, any amount, either sign | `mark_paid`, only the whole balance (`CollectBalance`) |
| Money handed back outside Stripe | the same `record_payment`, negative | a separate `record_refund` |
| Settled? | `payable?`, with a branch for refunded orders | nothing; pages read `balance` |
| Admin panel | the collect panel on the order page | built by hand per booking row in `courses_live.ex` |
| Can refund outside Stripe / with Stripe | `refundable_outside_stripe?`, `paid_through_stripe?` in the LiveView | `outside_stripe_refund/1`, `stripe_paid/1` in the other LiveView |

None of this is about flowers versus courses. Because an order's `balance` ignores cancelling, the order code corrects for it wherever it reads it (`payment_status`, `payable?`, `owes_money?`, `refundable_outside_stripe?`, `order_payment_badge` through `amount_mismatch?`), and it still misses one: a cancelled order paid by card has balance €0, so the order page offers no "Refund with Stripe" and Jennie goes to the Stripe dashboard. A cancelled booking gets the button.

Every feature that touches money has to say "orders do X, bookings do Y". The next one is a single list of what's owed either way, which today shows nowhere Jennie looks each day.

### Decisions

1. **Recording and settling money is one shared piece of each resource, an Ash fragment: `Edenflowers.Payments.Payable`.**
   As on Shopify and Magento, one ledger serves everything sold. Both `Order` and `CourseRegistration` include it with `fragments: [Edenflowers.Payments.Payable]`. Taking money stays per resource, because it does depend on what's sold: checkout, the payment link, seat holds, saved cards and customer self-cancel are untouched.
   Each resource supplies three things the fragment builds on:
   - `has_many :payments` (the foreign key differs).
   - `calculate :total_due`: what it's still to be paid for. An order: `grand_total`, 0 once cancelled. A booking: its seat share, 0 once cancelled, as today. The total itself stays as ordered, for receipts and the VAT breakdown. Only cancelled goes to 0, not an unplaced cart: checkout prices its PaymentIntent from `balance` when loaded (`Payments.expected_amount/1`).
   - `calculate :committed?`: whether money is owed on it at all. An order: placed. A booking: confirmed or cancelled; a pending booking is a seat hold.

2. **The fragment defines what's owed, once.**
   - Aggregates `amount_paid` and `paid_outside_stripe`, both defaulting to 0. An order's `amount_paid` is nil today when nothing was paid; readers that use nil as "never paid" (`pay_live.ex`, the order details email, the dashboard's Unpaid badge) check for a positive amount instead.
   - `balance`: `total_due - amount_paid`. Positive is to collect, negative is to refund.
   - `refunded?`: it took money and has handed all of it back.
   - `settled?`: `balance == 0 or refunded?`. A record refunded in Stripe without being cancelled reads as owed again by its balance, but is settled.
   - `outside_stripe_refund`: the most Jennie can record handing back, `min(-balance, paid_outside_stripe)`, 0 when nothing is to refund.
   - `stripe_refund`: what `Payments.refund_balance/1` sends back, the balance as far as Stripe payments cover it. The panel's "Refund with Stripe" confirmation names it.
   - `stripe_refundable?`: `stripe_refund > 0`.

3. **The fragment has the actions that record money, the same on both.**
   - `record_payment`, with `amount` and `payment_method`: money Jennie took or handed back by any method except Stripe. Refused unless `committed?`. An amount never takes the balance past zero, which also refuses a payment on a cancelled record, and a refund is only recorded while something is owed back. A refund is also capped at `paid_outside_stripe` (`RefundCoveredOutsideStripe`). Cancels any open PaymentIntent, since the link charged the old balance.
   - `undo_payment`, with `payment_id`: takes back a payment or refund Jennie recorded by mistake, by recording the opposite amount by the same method, pointing at it (`Payment.reverses_payment_id`, unique). Not for Stripe payments, nor an undo itself. A refund can't do this: a mistaken full payment leaves nothing owed, so a refund of it would be refused as a goodwill refund. An undone payment and its undo don't make a record `refunded?`.
   - `record_stripe_refund`, as both resources have it today.
   What Jennie records never takes the balance past zero, which closes two things orders allow today. An overpayment (a tip in cash) isn't a sale and is refused. A goodwill refund on something that still stands is refused until the order or booking is lowered first: edit the order, remove a seat, or cancel; then the refund settles it, and the monthly report sees a lower sale rather than a refund against an unchanged one. A refund made in the Stripe dashboard is still recorded whatever it is, because the money moved; one beyond what was owed back leaves a balance to collect, which the Overview shows Jennie. (Replaced by `TASK-14`: a refund on a settled record is a goodwill refund, and the part of a Stripe refund beyond what was owed back is goodwill.) A full refund reads settled through `refunded?`, as orders do today.
   Bookings lose `mark_paid`, `record_refund` and `CollectBalance`: marking a booking paid at the course is `record_payment` with the balance prefilled. `Orders.record_payment` and the Courses code interface expose the same action.

4. **Orders keep only what's about taking money, built on the shared pieces.**
   - `payable?` (the payment link can charge): `balance > 0 and not refunded?`.
   - `payment_status`: `:refunded` when `refunded?`; `nil` when cancelled and nothing was paid; otherwise `:paid` when `balance <= 0`, `:pending` when not.
   - `amount_mismatch?` goes; `order_payment_badge` reads `settled?`, and `ReportAmountMismatch` compares `amount_paid` with `grand_total` itself.

5. **The admin has one balance panel, on the order page and on each booking.**
   A component in the admin components that takes a record: "To collect" or "To refund" with the amount, "Refund with Stripe" when `stripe_refundable?`, and the record-a-payment-or-refund form prefilled with the balance, or with `outside_stripe_refund` for a refund. Shown when the record isn't `settled?`. A slot lets the order page add its payment link buttons. Both LiveViews lose their own helpers for this (`owes_money?`, `refundable_outside_stripe?`, `paid_through_stripe?` for refunding, `refund_outside_stripe`, `stripe_paid`, `outside_stripe_refund`). A cancelled order paid by card gets "Refund with Stripe" from the panel, with no new cancel dialog.
   At the course, recording a payment stays a quick action on the booking row, as today: method plus one tap, the amount filled in, with the "To collect" badge. So the courses page shows the panel only on a booking to refund, full width under its row; a list of panels made every row three times taller and repeated the quick action. Undoing a payment is in the order's payments list and in the booking's menu.
   The courses page lists past courses, marked past, while any booking on them is unsettled, so the Overview's booking rows always land on their course.

6. **The Overview shows one "To collect / To refund" widget.**
   In the right-hand column under "This month", hidden when nothing is owed. Two groups, each headed by its count and sum, then one row per record, largest first: who, the order or which course, the amount, linking to the order page or the course on the courses page. Both lists read `committed? and not settled?`. Each is a read action in its domain; the LiveView only merges and groups.
   It refreshes on the `admin:orders` broadcast the Overview already subscribes to. Booking changes don't broadcast there, so a booking settles on the Overview at the next page load; accepted.

7. **CONTEXT.md and ADR 0002 say it once.**
   CONTEXT.md: **Balance** says a cancelled order's or booking's total due is zero. Add **Total due**: what a placed order or confirmed booking is still to be paid for, before what's been paid is taken off; zero once cancelled. _Avoid_: amount due, outstanding. Add **Settled**: nothing is owed either way, or everything taken was handed back. ADR 0002 gets an amendment (written with this spec).

### Out of scope

- A full payments ledger page. The monthly report's income sheet is that ledger.
- Payment links for bookings, and customer self-cancel for bookings. Both are ways of taking or returning money, which stay per resource.
- Refunding at cancel time. The panel offers it right after.
- Booking broadcasts to the Overview.
<!-- SECTION:DESCRIPTION:END -->
