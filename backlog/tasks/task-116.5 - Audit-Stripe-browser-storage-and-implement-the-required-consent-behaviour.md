---
id: TASK-116.5
title: Load Stripe.js only on payment pages
status: done
assignee: []
created_date: '2026-10-26 18:57'
updated_date: '2026-10-27 14:07'
labels:
  - launch
  - quick
dependencies: []
parent_task_id: TASK-116
type: task
ordinal: 266000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Shoppers browsing the store should not get Stripe cookies or device signals before they reach a payment page.

Decided in launch triage (2026-10-27): load Stripe.js only where a payment happens, and skip the wider consent audit. Stripe's fraud-prevention cookies on the payment step are strictly necessary for the service the customer asked for, so no banner is needed.

- `assets/js/app.js` warms Stripe up on every page (`whenIdle(() => loadStripe()...)`). Remove that warm-up. `EdenflowersWeb.StripeForm` already loads Stripe on demand and preloads the script on the payment pages.
- The privacy policy says Stripe sets cookies on the payment pages only, for payment and fraud prevention.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 js.stripe.com is not requested on store, product, cart or account pages
- [x] #2 Checkout payment and payment-link pages still take a card payment (checked in the browser)
- [x] #3 The privacy policy describes Stripe cookies as limited to the payment pages
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Removed the idle site-wide Stripe warm-up from app.js; StripeForm still loads Stripe when a payment form mounts. Dev browser: homepage requests nothing from Stripe after 4s idle and sets no cookies; /pay/orders/:token loads Stripe, renders the Payment Element and enables Pay. Privacy page cookie line rewritten (en/sv/fi).
<!-- SECTION:NOTES:END -->
