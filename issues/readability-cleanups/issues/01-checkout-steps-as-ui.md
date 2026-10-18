# Decide whether checkout's steps stay as order states

Status: needs-triage
Type: grilling

## Problem

`Order`'s state machine stores which checkout step the customer is on: `contact_details → gift_options → delivery → payment`, with `return_to_contact_details`, `return_to_gift_options`, `return_to_delivery` and `restart_checkout` to step back. Around them sit `ResetCheckout`, `PrefillFromLastOrder`, `ensure_fulfillment_default` in `CheckoutLive`, the `@checkout_states` policies, and `finalize_checkout` accepting any step "because the customer has paid".

## The idea

The steps become sections of one checkout page, held in the LiveView. The order keeps only `cart → placed`. Each section saves its fields as the customer goes, and validation that has to hold runs once before the PaymentIntent is created.

## To decide

- Does the stepped flow matter to customers? It's what they see today, and it suits phones.
- Could the steps stay visually while their state moves out of the database? That keeps the UX and drops the transitions.
- Cost: `CheckoutLive` (1,150 lines) and its tests are the bulk of the change.

## Comments
