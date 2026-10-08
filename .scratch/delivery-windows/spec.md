# Delivery Windows

Status: needs-triage
Parked: 2026-10-07. Design agreed in a grilling session, not yet broken into issues.

## Problem

An order only has a `fulfillment_date`; there is no time of day. Customers ask for specific times (funerals, office hours, occasions), Jennie already arranges them by hand through the Florist Note and phone calls, and an extra fee for the certainty is welcome revenue.

## Proposed term

**Delivery Window**: a time range on the delivery date that the Customer pays extra to have the delivery arrive within. Optional; without one, the delivery arrives any time that day.
_Avoid_: time slot, timed delivery

Add to `CONTEXT.md` when this is picked up.

## Decisions

1. **A window is a choice layered on a delivery option, not its own `FulfillmentOption`.**
   Rejected: modelling "Delivery, morning (9–12)" as extra options with a higher `base_price`. It works today with zero code, but clutters checkout and duplicates per-km pricing across options. Worth remembering as the zero-code fallback.

2. **Windows live as an embedded list on `FulfillmentOption`** (`windows: [%{id, label, from, to, surcharge}]`), with a stable id per window and labels translated through the existing `translations` block. Set via seeds or the console, like option prices today. Pickup options have none.
   Rejected: a hardcoded module (windows depend on the option; labels need translating) and a `DeliveryWindow` resource with an admin editor (Jennie doesn't edit prices herself either).

3. **The surcharge folds into `fulfillment_fee`.** `CalculateFulfillmentCost` and `PriceFulfillment` add it to the distance fee, so VAT (the option's `tax_rate`), `fulfillment_fee_override`, Balance and payments are unchanged. The receipt's single delivery line carries the window, e.g. "Delivery, 9–12".
   The order snapshots the window's label, start and end (like `fulfillment_option_name`) so later edits to the option don't rewrite past orders. The surcharge amount is not snapshotted.

4. **Choosing a window is optional.** Checkout's delivery step defaults to "Any time during the day (included)". Window fields stay nil otherwise, so existing orders need no backfill.

5. **Windows are for future dates only at checkout.** Same-day orders get "any time" only. The rule is enforced server-side in `submit_delivery` and again at payment, not only in the UI, so a stale cart can't keep a window that's no longer allowed.

6. **No capacity limit per window.** If a window gets crowded, Jennie phones the customer.

7. **Admin:**
   - The order form gets the same window select. The window fields join `@priced_by` in `PriceFulfillment`, so changing the window reprices the order and the existing Balance / Payment Link flow handles the difference.
   - Jennie may set a window on a same-day order; the future-only rule protects customers, not her.
   - Changing the option clears the window (`update_fulfillment_option` and the order form). Changing the date does not.
   - The window shows next to the date on the orders list, order detail, fulfillment calendar, and in customer emails.

8. **A missed window is refunded by hand.** Jennie refunds the surcharge in Stripe, recorded as a negative Payment (ADR 0002). Checkout states the policy in one line: "If we miss your window, we refund the surcharge."

## Deferred until needed

- Per-window capacity with a race guard: add after the first real double-booking.
- Same-day windows: reuse the option's `order_deadline` (only windows starting after it) if customers ask.
- An admin editor for windows: when Jennie wants to change them without a deploy.
- Recording an arrival time and refunding automatically.
