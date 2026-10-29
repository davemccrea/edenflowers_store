# Placed is not the same as paid

An Online Order becomes placed only when Stripe confirms payment, so for years "placed" and "paid" happened together. Custom Orders are placed the moment Jennie saves them, because they are often paid later, via a payment link or in person at collection, and Jennie has already committed to making them. Payment status is therefore tracked separately from placement, and anything that means "orders Jennie must make" must not filter on payment.

The same holds for course bookings: Jennie accepting a booking commits the shop to the places, paid or not.

## Consequences

- Fulfilment views include unpaid placed orders and flag them as unpaid.
- Sales figures report money received, not commitments (ADR 0002).
- Payment reconciliation must also cover placed Custom Orders that still have an outstanding payment link.
