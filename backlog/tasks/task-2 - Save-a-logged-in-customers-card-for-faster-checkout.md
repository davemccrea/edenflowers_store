---
id: TASK-2
title: Save a logged-in customer's card for faster checkout
status: done
assignee: []
created_date: '2026-10-09 02:13'
updated_date: '2026-10-18 07:27'
labels: []
dependencies: []
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Save a logged-in customer's card for faster checkout

Implemented 2026-10-15; needs a real Stripe check (see Comments).

### Problem

A logged-in customer types their card details at every checkout. Subscriptions already save a card to a Stripe Customer for off-session charges, but one-off orders never do, and the User has no Stripe Customer of its own.

### Decisions

1. **Cards live on our Stripe account's Customer, linked from the User. Not Link.**
   Link keeps the card in Stripe's consumer network, shared across merchants; we'd rather keep it in house. Card numbers never touch our servers (PCI), so a Stripe Customer we own is as in house as it gets.
   Turn Link off in the Dashboard (Settings → Payment methods), not in code, so `automatic_payment_methods` keeps picking up new methods.

2. **The Payment Element does the UI, through a CustomerSession.**
   `Stripe.CustomerSession` (stripity_stripe 3.3.2) with `payment_element` features `payment_method_save: "enabled"` and `payment_method_remove: "enabled"`. Stripe renders the saved cards, the "save card" checkbox and removal; `hooks.js` passes the session's client secret to `stripe.elements` alongside the PaymentIntent's.
   Rejected: our own checkbox, a separate `confirmCardPayment` path for saved cards, and an account page to list and remove cards.

3. **`stripe_customer_id` on User, created lazily** the first time a logged-in user reaches payment, then reused. The one-off PaymentIntent gets `customer:` set. Guests get no Customer and no CustomerSession.

4. **The Customer is always looked up from the actor, never from params.** A user can only ever see or charge cards on their own Customer. This is the one test that must exist: a logged-in user's PaymentIntent and CustomerSession carry their Customer; a guest's carry none.

5. **Subscriptions keep their own Customers.** `Payments.create_payment_intent` still creates a fresh Customer per subscription order. Removing a card in the Payment Element therefore can't pull the card out from under a Subscription, and no delete guard is needed.

6. **`Payments.setup/2` also checks the Customer.** Its `setup_future_usage` check is unchanged: a card saved through the checkbox on a one-off order is at most `on_session`. A signed-in user's one-off PaymentIntent must also carry their Customer, so one opened before they signed in is replaced.

### Deferred until needed

- Sharing one Customer between one-off orders and subscriptions (start a subscription on a card saved at checkout): add when customers ask. Needs a guard so removing a card can't break a live Subscription.
- Managing cards on the account page: add if customers want it outside checkout.
- Backfilling existing subscription Customers onto Users.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @david
created: 2026-10-17 16:14

---

2026-10-15: Implemented. Still to do by hand:
- Turn Link off in the Stripe Dashboard (Settings → Payment methods), test and live.
- Check in test mode with a signed-in user: save a card, come back, see it listed, remove it.

---

author: @claude
created: 2026-10-18 04:44

---

2026-10-18: David checked saved cards on staging in test mode (save, see listed, remove). Still to do: turn Link off in the Stripe Dashboard, test and live.

---

author: @claude
created: 2026-10-18 04:46

---

2026-10-18: Link turned off in the Stripe Dashboard. Done.

---
<!-- COMMENTS:END -->
