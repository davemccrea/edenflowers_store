# Payments are records, not a column on the order

An order can be paid more than once: a custom order paid later, a balance left by editing an order after it was paid, a refund. A single `amount_paid` and `payment_method` on the order could hold one payment, and a webhook redelivery was only made harmless by refusing to pay an order twice. So each payment is a `Payment` row (negative for a refund), and what's paid and still owed is worked out from the rows. A unique Stripe id on each row is what stops Stripe's at-least-once delivery from counting money twice.

Course bookings use the same ledger. A `Payment` belongs to either an order or a course registration, never both, and both share one fragment, `Edenflowers.Payments.Payable`, for balance, settlement, refunds and recording payments. How money is taken stays per resource, because that depends on what's sold.

## Considered Options

- **A polymorphic parent reference on `Payment`.** Rejected: two foreign keys keep references and joins honest in the database.
- **A shared parent table for orders and bookings.** Rejected for the same reason; a fragment shares the behaviour without it.
- **Separate money code for orders and bookings.** This is what existed, and the two disagreed about balances, refunds and how Jennie recorded payments.

## Consequences

- Only money that moved is a row. A payment the customer hasn't finished stays on the parent until it succeeds.
- A succeeded payment is always recorded, even on a cancelled or already-paid purchase, and reported so Jennie refunds it. It never reopens fulfilment or rebooks places.
- A payment that doesn't match what it lands on still confirms it, and the difference is left as a Balance for Jennie. That's rare enough to settle by hand, and simpler than cancelling and replacing payments to keep amounts exact.
- A paid flag or payment status disconnected from the rows is never added.
- Sales revenue counts payments by when the money moved, not orders by when they were placed.
