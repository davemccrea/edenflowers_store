---
id: TASK-171
title: Retry outstanding subscription payment after updating the card
status: needs-triage
assignee: []
created_date: '2026-11-03 09:14'
labels:
  - spec
  - customers
  - admin
dependencies: []
references:
  - docs/adr/0003-subscriptions-create-ordinary-orders.md
priority: medium
type: feature
ordinal: 319000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Customers recover a failed subscription payment by updating their saved card and having the outstanding order charged again in the same flow.

**Why:** The current email asks customers to pay through one link and update their card through another. One recovery action would make it easier to settle the missed payment and keep future flowers coming.

## Current behaviour
- The payment-failure email offers separate payment and account links.
- SubscriptionCardLive saves a replacement card through a SetupIntent. Payments.save_subscription_card runs on both the browser return and setup_intent.succeeded.
- Subscription.replace_card saves the new card and reactivates a held subscription, but deliberately leaves existing unpaid orders outstanding. The card page explicitly explains this.
- The shop manages subscriptions itself, outside Stripe Billing. Replaying occurrence creation does not implement recovery for an already placed unpaid order.

## Proposed outcome
- Offer one primary recovery action in the failure email, leading to the affected subscription/order.
- Before confirmation, show the amount and explain that saving the card will also retry the outstanding payment.
- After saving the card, collect the eligible order's current outstanding balance and use normal payment recording and receipt delivery.
- Recheck ownership, order eligibility and balance before charging. Handle payments through older links, partial payment, refunds, cancellation and payments in flight.
- Browser returns, duplicate webhooks, concurrent payment-link attempts and job retries must not duplicate charges or receipts. Reconcile uncertain charge outcomes before another attempt.
- Handle bank authentication and a second decline with a clear recovery route; do not claim payment succeeded prematurely.
- Update email, account notices and card-page copy together in Swedish, Finnish and English. Keep older payment links safe.

## Triage remaining
This is a proposal from the 3 November email-copy discussion, not an implementation-ready decision. Confirm whether automatic retry applies only when entered through payment recovery or also to ordinary card updates; which order(s) to collect if several unpaid occurrences exist; and whether future deliveries stay held until settlement. Current card replacement reactivates immediately, although the failure email says later deliveries are held until payment. Decide retry scheduling and authentication fallback. Keep needs-triage until the repository grilling workflow establishes shared decisions.

## Context
Keep this independent of the approved invoice and outstanding-payment copy edits. TASK-170 covers editable admin email drafts.
Relevant code: lib/edenflowers_web/features/account/subscription_card_live.ex; lib/edenflowers/payments.ex; lib/edenflowers/orders/subscription.ex; lib/edenflowers/orders/subscription/changes/create_occurrence.ex; lib/edenflowers/email/templates/subscription_payment_failed.text.eex. ADR 0003 describes subscription occurrences.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The agreed recovery flow saves the replacement card and attempts the eligible outstanding payment without asking the customer to enter payment details twice.
- [ ] #2 The page explains the amount and retry before confirmation; domain actions enforce ownership, order eligibility and current balance.
- [ ] #3 Successful recovery records payment and sends the normal receipt once; subscription state follows the agreed recovery policy.
- [ ] #4 Repeated callbacks, retries and concurrent payment-link completion cannot double-charge or duplicate receipts; uncertain outcomes are reconciled.
- [ ] #5 Authentication-required and declined payments provide actionable recovery without falsely reporting success.
- [ ] #6 Failure emails and account/card pages agree with the behaviour in all three languages; older payment links remain safe.
- [ ] #7 Domain and flow coverage verifies success, partial/already-paid and cancelled orders, duplicate callbacks, concurrency and authentication/failure outcomes.
<!-- AC:END -->
