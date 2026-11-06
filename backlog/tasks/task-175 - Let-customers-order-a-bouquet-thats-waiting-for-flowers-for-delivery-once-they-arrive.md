---
id: TASK-175
title: >-
  Let customers order a bouquet that's waiting for flowers, for delivery once
  they arrive
status: done
assignee: []
created_date: '2026-11-06 12:13'
updated_date: '2026-11-06 12:33'
labels:
  - spec
  - customers
  - admin
dependencies: []
priority: high
type: feature
ordinal: 340000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When a bouquet runs out of flowers, customers can still order it, for delivery or pickup from the day the next flower delivery lets Jennie make it.

**Why:** Today Jennie marks a bouquet out of flowers by setting its Stock to 0, which makes it Sold out and unbuyable, though she can make it again in 1-4 days. Customers who would happily wait for it leave instead.

## Domain
- New term **Available from** (CONTEXT.md, beside Stock): the first day a made-to-order product can be made again, after the next flower delivery. Nil, or a day already past, means it can be made now. It never makes a product sold out; it only pushes back its earliest fulfillment day. Stock keeps meaning finite items on the shelf, and Stock at 0 stays Sold out.
- A date attribute on Product (whole product, not per size: every size uses the same flowers). It stops applying once the day comes, so nothing clears it.
- Order gets a calculation for its earliest fulfillment day: Availability.next_open_date/3 from the latest Available from among its lines (the voucher card already uses `from` this way). The FulfillmentDate validation refuses earlier days for Online Orders, so checkout and the action agree.
- One order, one date: a cart mixing a waiting bouquet with things available today waits for the bouquet.
- Not held to it: Custom Orders (Jennie decides) and subscription Occurrences (made fresh; she plans their flowers into her wholesale order). A subscribable product's first, checkout-paid order is a normal Online Order and is held to it.

## Storefront
- Product card: no greying out; a line "Available from Tue 10 Nov" ("tomorrow" when it is, like the pay page).
- Product page: sizes stay pickable and Add to cart stays live; "Available from Tue 10 Nov" by the button.
- Checkout calendar: days before the order's earliest day read as unavailable, with one line naming the product that pushes it back. A date picked before Jennie set Available from is refused with that line.
- schema.org offer: PreOrder with availabilityStarts instead of InStock.

## Admin
- The product form's "Sold out" button becomes an "Available from" date input, blank by default, with a way to clear it. It stops filling sizes' Stock with 0.
- Products list shows "From Tue 10 Nov" for a waiting product.

Decisions grilled 2026-11-06.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A product with Available from in the future can be added to the cart and checked out
- [x] #2 Checkout refuses a fulfillment day before the order's earliest day, server-side, and the calendar shows those days unavailable with a line naming the product
- [x] #3 Product card and page show 'Available from <date>' instead of Sold out, and the product is not greyed out
- [x] #4 Available from in the past or nil behaves as today; no job clears it
- [x] #5 Custom Orders and subscription Occurrences ignore Available from
- [x] #6 Stock at 0 still means Sold out, unchanged
- [x] #7 Admin product form sets and clears Available from; the Sold out button no longer zeroes Stock
- [x] #8 CONTEXT.md defines Available from beside Stock; sv/fi strings translated
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built 2026-11-06. Product.available_from (date) + waiting_until calc; Order aggregate available_from (future only); Availability.unavailable_reason/4 :before_available_from feeds checkout validation, payment re-check and StoreCalendar. Admin Sold out button removed; date input on the product form. Copy trimmed at David's request: no admin help text, checkout says only '<product> is available from <date>.' Before release: reset prod bouquets with stock_quantity 0 used as 'out of flowers' to nil.
<!-- SECTION:NOTES:END -->
