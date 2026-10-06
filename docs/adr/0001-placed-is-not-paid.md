# Placed is not the same as paid

An Online Order becomes placed only when Stripe confirms payment, so for years "placed" and "paid" happened together. Custom Orders are placed the moment Jennie saves them, because they are often paid later — via a payment link, or in person at collection — and Jennie has already committed to making them. Payment status is therefore tracked separately from placement, and anything that means "orders Jennie must make" must not filter on payment.

## Consequences

- Fulfilment views include unpaid placed orders and flag them as unpaid.
- Sales figures still count only paid orders: they report money received, not commitments.
- Payment reconciliation must also cover placed Custom Orders that still have an outstanding payment link.
