# Purchases and standalone invoices are the sales record

The monthly report is the accountant's single source of sales and VAT. Store orders and course bookings describe shop purchases; standalone invoices describe occasional weddings and bespoke work without inventing a purchase. Each Payment belongs to exactly one of these three sources, so recording an invoice receipt cannot also count it as a purchase receipt. The payment services supply fees and payouts for bank reconciliation, never a second sales total.

VAT remains cash based: sales enter the report on each Payment's Helsinki paid date. Issuing an invoice freezes its own billed lines and numeric gross, base and VAT per rate, but adds no cash sale. Crediting an unpaid invoice adds no receipt or refund. Month-end receivables reconstruct unpaid issued invoices from document dates, credits and dated Payments; drafts never count.

Invoice receipts use the frozen financial breakdown. In paid-date order (ties by payment id), cumulative gross is allocated by each rate's share, rounded half up to cents, with the residual on the largest gross rate (ties to the lower VAT rate). Cumulative base uses the frozen base/gross proportion within each rate, and VAT is gross minus base. Each receipt reports the difference between cumulative allocations before and after it. This makes final settlement reproduce the frozen VAT exactly and lets reversals return to zero without accumulated rounding drift; zero-gross rates allocate zero.

## Considered Options

- **Each payment service is its own sales record.** Rejected: Zettle, Stripe and bank receipts could then count sales already recorded in the shop, while cash and MobilePay have no separate VAT record.
- **Every bespoke invoice requires a store order or booking.** Rejected: that ties invoice lines, VAT and payments to purchase balances and makes ordinary wedding booking and remainder invoices unnecessarily complex.
- **Count issued invoices as sales alongside their receipts.** Rejected: this double counts sales and contradicts the existing cash-based accounting convention.

## Consequences

- The accountant books sales only from the monthly report, never also from payment-service reports or a separate invoice total.
- Placed orders, confirmed bookings, issued invoices and payment history are retained. Corrections preserve the original records; paid invoice corrections go to the accountant.
- A Zettle sale without an order remains missing from the report. Comparing Zettle's totals with recorded Zettle payments would catch omissions; that check is not built yet.
- Retention for accounting does not itself define a privacy retention period.
