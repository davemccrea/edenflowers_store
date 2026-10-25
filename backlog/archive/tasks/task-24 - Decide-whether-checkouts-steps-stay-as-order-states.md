---
id: TASK-24
title: Decide whether checkout's steps stay as order states
status: done
assignee: []
created_date: '2026-10-18 11:35'
updated_date: '2026-10-18 14:39'
labels:
  - spec
  - developers
dependencies: []
priority: medium
type: grilling
ordinal: 79000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Checkout's steps stay as they are on the order, or move into the page so the order only goes from cart to placed

**Why:** Storing the checkout step on the order brings a set of transitions, resets and policies. If the steps don't need to live in the database, most of that goes.

### Problem

`Order`'s state machine stores which checkout step the customer is on: `contact_details → gift_options → delivery → payment`, with `return_to_contact_details`, `return_to_gift_options`, `return_to_delivery` and `restart_checkout` to step back. Around them sit `ResetCheckout`, `PrefillFromLastOrder`, `ensure_fulfillment_default` in `CheckoutLive`, the `@checkout_states` policies, and `finalize_checkout` accepting any step "because the customer has paid".

### The idea

The steps become sections of one checkout page, held in the LiveView. The order keeps only `cart → placed`. Each section saves its fields as the customer goes, and validation that has to hold runs once before the PaymentIntent is created.

### To decide

- Does the stepped flow matter to customers? It's what they see today, and it suits phones.
- Could the steps stay visually while their state moves out of the database? That keeps the UX and drops the transitions.
- Cost: `CheckoutLive` (1,150 lines) and its tests are the bulk of the change.
<!-- SECTION:DESCRIPTION:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Decided: the steps stay as order states. CheckoutLive mirrors the step in the URL (/checkout?step=...), so the browser's back button steps back through checkout. A URL step before the order's state calls the matching return_to_* action; any other is replaced with the order's state, as only Next moves the order forward. Browser forward was left out: it is rarely used, and after going back the customer presses Next with their details still filled in.

Moving the steps out of the database was parked. What it would cost:
- Nothing server-side would guarantee an order passed every submit_* validation before it gets a PaymentIntent. A checkout_complete? check before Payments.setup and in pay would have to repeat them all.
- :payment means more than the step. OrderLive lets the owner wait for the webhook on it, and an Occurrence is created in it and placed from it by place_unpaid_occurrence, so the order would still need a middle state.
- The cart drawer's Continue checkout label and delivery_fee's quote-or-stored choice read the state.
- Orders in checkout at deploy would need their states mapped, keeping :payment orders with an open PaymentIntent placeable.
The only gain over the URL mirror is browser forward working.
<!-- SECTION:FINAL_SUMMARY:END -->
