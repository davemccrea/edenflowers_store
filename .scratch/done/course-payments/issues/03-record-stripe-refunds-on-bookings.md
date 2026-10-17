# Stripe refunds on course bookings are recorded

Status: done
Type: bug

## What to build

Decision 4 of the spec for Stripe refunds. Jennie refunds course bookings in the Stripe dashboard today and nothing is recorded.

- `Payments.record_refund/1` finds the `Payment` by `payment_intent_id` and records the refund as a negative `:stripe` row with its `stripe_refund_id` against that payment's parent, order or registration. It no longer ignores course bookings.
- `Payments.sync_refunds/1` works for a registration too, so a refund whose webhook never arrived can be picked up.

## Acceptance criteria

- [ ] A Stripe refund on a booking is recorded once as a negative `Payment`, even with webhook redelivery
- [ ] A partial refund records only the refunded amount
- [ ] Order refunds behave exactly as before

## Blocked by

01
