---
id: TASK-145
title: Confirm the live Stripe webhook sends every event the shop relies on
status: ready-for-human
assignee: []
created_date: '2026-10-29 14:10'
updated_date: '2026-10-30 17:28'
labels:
  - spec
  - admin
  - quick
dependencies: []
priority: high
type: chore
ordinal: 279000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Before full production, check in the Stripe dashboard (live mode) that the webhook endpoint for https://edenflowers.fi/webhook/stripe exists and subscribes to every event `EdenflowersWeb.Webhooks.StripeHandler` acts on.

**Why:** a paid order is placed, its receipt emailed and Jennie notified only when Stripe reports the payment. A missing event means refunds made in the Stripe dashboard aren't recorded, and subscriptions never get their saved card. The 10-minute reconcile job catches missed payments, but only after a delay and never refunds or saved cards.

Events the handler needs:
- `payment_intent.succeeded`: places checkout orders and course bookings, records payment link payments
- `payment_intent.canceled`: clears a cancelled PaymentIntent so checkout can open a fresh one
- `refund.created` and `refund.updated`: record refunds, including ones made in the Stripe dashboard
- `setup_intent.succeeded`: saves a subscription's card

`payment_intent.payment_failed` and `charge.succeeded` are acknowledged but do nothing, so subscribing to them is harmless and not required.

Checked in test mode on 2026-10-29: a checkout, a redelivered event and a declined card all behaved correctly through `stripe listen`. That doesn't show what the live endpoint is subscribed to.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The live-mode endpoint for https://edenflowers.fi/webhook/stripe subscribes to payment_intent.succeeded, payment_intent.canceled, refund.created, refund.updated and setup_intent.succeeded
- [ ] #2 The endpoint's API version is 2025-11-17.clover, the version stripity_stripe 3.3.2 calls Stripe with. If not, create a new endpoint on that version, put its signing secret in vault_stripe_webhook_secret, deploy, then delete the old endpoint
- [ ] #3 The endpoint's event log shows a 200 delivery for payment_intent.succeeded from a real live order, and 200s for refund.created and refund.updated from refunding one in the admin. Use existing live deliveries if there are any; otherwise place a small real order and refund it. A 200 also proves the signing secret matches the vault, since the handler rejects bad signatures
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Grilled 2026-10-30: done by hand in the Stripe dashboard (the CLI's live key expired 2026-01-17). The separate signing-secret check was folded into the delivery check. setup_intent.succeeded is checked by subscription only, not by a live subscription signup.
<!-- SECTION:NOTES:END -->
