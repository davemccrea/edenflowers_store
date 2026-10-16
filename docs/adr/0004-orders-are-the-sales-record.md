# Orders are the sales record, not the payment services

Sales reach the shop through Stripe, Zettle, Zervant invoices, MobilePay and cash, and Zettle and Zervant each keep their own sales records with VAT. Booking from each service would mean several sources the accountant must combine without counting any sale twice, and MobilePay and cash have no record with VAT at all. So every sale, over-the-counter ones included, is entered as an order, and the orders are the only record the shop's sales are booked from. The payment services are only ways of getting paid: what the accountant takes from them is fees and payouts, to match the bank.

## Considered Options

- **Each service is the record of its own sales.** Rejected: payments recorded on orders would have to be left out wherever another service also holds them, and that boundary moves whenever the accountant's setup does.
- **Pull Zettle's purchases into the monthly report.** Rejected: Zettle purchases don't link to orders, so telling a walk-in sale from a Zettle payment already on an order would rest on fragile matching.

## Consequences

- The accountant books sales only from the monthly report, never also from Zettle's or Zervant's own reports.
- A Zettle sale with no order is missing from the VAT return. Comparing Zettle's own sales total with the Zettle payments recorded on orders would catch a forgotten order; that check is planned for the monthly report but not built yet.
