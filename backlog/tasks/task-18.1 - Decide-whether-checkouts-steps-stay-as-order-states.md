---
id: TASK-18.1
title: Decide whether checkout's steps stay as order states
status: needs-triage
assignee: []
created_date: '2026-10-18 03:08'
updated_date: '2026-10-18 07:28'
labels: []
dependencies: []
parent_task_id: TASK-18
type: grilling
ordinal: 52000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
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
