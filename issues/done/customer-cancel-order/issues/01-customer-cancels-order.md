# Customer cancels their order from the account page

Status: done

## What to build

A signed-in customer can cancel one of their own Online Orders from the account page until 4 days before its fulfillment date, which refunds what they paid in full through Stripe.

- **Which orders:** placed, pending, one-off Online Orders belonging to the customer, paid only through Stripe. Never Custom Orders, never orders with an In-person Payment. Whole order only.
- **Cut-off:** fulfillment date after today + `Subscription.cutoff_days` (4), Helsinki time. Same rule as subscription changes. Subscription occurrences are created past this cut-off, so they are never cancellable here; pause/change covers them.
- **Subscription's first order:** cancelling it leaves the subscription alone.
- **Refund:** everything paid is refunded through Stripe, across payments, as `Payments.refund_balance` does. The refund must succeed (or be pending at Stripe) before the cancel commits. If it fails, the order stays placed, the customer is asked to contact the shop, and Jennie gets an error alert.
- **Stock** goes back, as with Jennie's cancel.
- **Domain:** a new `:cancel_by_customer` action on Order with the rules in the resource, so PaperTrail shows who cancelled. Jennie's `:cancel` stays "never refunds". CONTEXT.md gets the new rule.
- **Promotions:** `Promotion.usage` no longer counts cancelled orders, so a single-use code comes back (also when Jennie cancels).
- **Email:** "Order cancelled" to the customer stating the refund, BCC the shop.
- **Account page:** a cancellable order shows "You can cancel until <date>" and a **Cancel order** button, with a confirmation dialog stating the refund amount and that it can take 5–10 days. Nothing shown past the cut-off.
- **Policy:** an FAQ entry, and a line in the order confirmation email for signed-in customers whose order is still cancellable.

## Acceptance criteria

- [ ] A customer cancels their eligible order; it is cancelled, refunded in full, stock returned, and they get the email (shop BCC'd)
- [ ] An order 4 days or fewer away shows no cancel option and the action refuses it
- [ ] Custom Orders, orders with an In-person Payment, and other customers' orders can't be cancelled by the customer
- [ ] A failed Stripe refund leaves the order placed and shows an error
- [ ] A single-use promotion used on a cancelled order can be used again
- [ ] FAQ and confirmation email describe the policy
