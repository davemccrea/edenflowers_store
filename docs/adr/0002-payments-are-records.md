# Payments are records, not a column on the order

An order can be paid more than once: a custom order paid later, a balance left by editing an order after it was paid, a refund. A single `amount_paid` and `payment_method` on the order could hold one payment, and a webhook redelivery was only made harmless by refusing to pay an order twice. So each payment is now a `Payment` row (negative for a refund), the order's `amount_paid` is their sum, and the balance is the total minus that. A unique PaymentIntent id, and refund id, on the row is what stops Stripe's at-least-once delivery from counting money twice.

## Consequences

- Only money that moved is a row. A PaymentIntent waiting for the customer stays on the order as `payment_intent_id` and is cleared once paid, so a later payment link opens a fresh one for the balance.
- A succeeded payment is always recorded, even for an order cancelled or already paid in person; it is reported as an error so Jennie refunds it.
- Refunds made in the Stripe dashboard arrive through the `refund.created`/`refund.updated` webhooks, which the Stripe webhook endpoint must be subscribed to.
- Sales revenue counts payments by when the money moved, not orders by when they were placed.
