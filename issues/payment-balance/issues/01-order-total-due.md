# A cancelled order owes nothing

Status: ready-for-agent
Type: refactor

## What to build

Decisions 1, 2 and 4 of the spec: an order's `balance` means what a booking's does, and the code that corrected for it goes.

- `Order` gets `calculate :total_due`: `grand_total`, or 0 when `fulfillment_status == :cancelled`. `balance` becomes `total_due - (amount_paid || 0)`.
- `payable?` and `payment_status` as in decision 2.
- Order page (`order_detail_live.ex`): the collect panel shows when `balance != 0`, cancelled or not. Its record-a-refund form is prefilled with the negative balance capped at `paid_outside_stripe`, as `CoursesLive.outside_stripe_refund/1`. Remove `refundable_outside_stripe?`, the `refund_outside_stripe` component and their branch in `payment_form/1`. The payment link buttons already need a positive balance, so a cancelled order never offers one.
- `order_payment_badge` (`components.ex:333`) reads `balance != 0`; update its `doc:`. Delete `amount_mismatch?` and drop it from the loads; `ReportAmountMismatch` compares `amount_paid` with `grand_total` directly.
- CONTEXT.md as in decision 4.

## Acceptance criteria

- [ ] A cancelled order paid €80 by card has balance −€80, shows "To refund €80" and a working "Refund with Stripe" button on the order page
- [ ] A cancelled order paid €80 in cash shows "To refund €80" with the record-a-refund form prefilled at −€80; one paid €50 by card and €30 in cash prefills −€30
- [ ] A cancelled order never paid has balance €0, no collect panel, and no payment status badge, as today
- [ ] An open order edited after payment still shows its balance to collect or refund, as today
- [ ] An order refunded in the Stripe dashboard without being cancelled reads Refunded and is not payable, as today
- [ ] Checkout and the payment link charge the same amounts as before
- [ ] Order receipts and the VAT breakdown are unchanged

## Blocked by

None - can start immediately
