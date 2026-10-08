# Saved Cards

Status: needs-triage
Parked: 2026-10-09. Approach agreed in conversation, not yet broken into issues.

## Problem

A logged-in customer types their card details at every checkout. Subscriptions already save a card to a Stripe Customer for off-session charges, but one-off orders never do, and the User has no Stripe Customer of its own.

## Decisions

1. **Cards live on our Stripe account's Customer, linked from the User. Not Link.**
   Link keeps the card in Stripe's consumer network, shared across merchants; we'd rather keep it in house. Card numbers never touch our servers (PCI), so a Stripe Customer we own is as in house as it gets.
   Turn Link off in the Dashboard (Settings → Payment methods), not in code, so `automatic_payment_methods` keeps picking up new methods.

2. **The Payment Element does the UI, through a CustomerSession.**
   `Stripe.CustomerSession` (stripity_stripe 3.3.2) with `payment_element` features `payment_method_save: "enabled"` and `payment_method_remove: "enabled"`. Stripe renders the saved cards, the "save card" checkbox and removal; `hooks.js` passes the session's client secret to `stripe.elements` alongside the PaymentIntent's.
   Rejected: our own checkbox, a separate `confirmCardPayment` path for saved cards, and an account page to list and remove cards.

3. **`stripe_customer_id` on User, created lazily** the first time a logged-in user reaches payment, then reused. The one-off PaymentIntent gets `customer:` set. Guests get no Customer and no CustomerSession.

4. **The Customer is always looked up from the actor, never from params.** A user can only ever see or charge cards on their own Customer. This is the one test that must exist: a logged-in user's PaymentIntent and CustomerSession carry their Customer; a guest's carry none.

5. **Subscriptions keep their own Customers.** `Payments.create_payment_intent` still creates a fresh Customer per subscription order. Removing a card in the Payment Element therefore can't pull the card out from under a Subscription, and no delete guard is needed.

6. **`Payments.setup/2` needs no change.** Its check compares `setup_future_usage` with `"off_session"`; a card saved through the checkbox on a one-off order is at most `on_session`.

## Deferred until needed

- Sharing one Customer between one-off orders and subscriptions (start a subscription on a card saved at checkout): add when customers ask. Needs a guard so removing a card can't break a live Subscription.
- Managing cards on the account page: add if customers want it outside checkout.
- Backfilling existing subscription Customers onto Users.
