---
id: TASK-88
title: Make free delivery cover the first 5 km of any trip
status: needs-triage
assignee: []
created_date: '2026-10-21 19:23'
labels:
  - spec
  - customers
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 182000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Free-delivery bouquets get the first `free_dist_km` (5 km) of their delivery free, however far it goes, and the store and admin say so: "First 5 km delivery free".

**Why:** The copy says "Free delivery within 5 km", but Jennie means the first 5 km are free. Today a free-delivery bouquet pays €0 up to 5 km, then the full fee (base + per_km × whole distance) just past it, so a customer at 5.1 km loses the whole perk.

## Today (since 1f80e5c5)
- Everyone pays `base_price + price_per_km × distance`.
- A cart with a free-delivery product pays €0 when distance ≤ `free_dist_km`, full price beyond (`Fee.calculate` sets `in_free_delivery_zone`, `Order.fee_for_cart` waives).

## Open business decision
What a free-delivery cart pays past 5 km:
1. **`price_per_km × (distance − 5)`**: the 5 km fee is deducted, no jump at the boundary, matches the words. Recommended.
2. `base_price + price_per_km × (distance − 5)`: jumps by the base price just past 5 km.
3. Full price (today): copy-only change, but "first 5 km free" would then be misleading.

Products without free delivery stay at `base + per_km × distance`.

## Copy to reword (en/fi/sv)
- Store: product page badge (`product_live.ex`), homepage meta description and delivery line (`home_live.ex`), FAQ delivery answer (`faq_live.ex`; it also omits that only chosen bouquets qualify).
- Admin: product form toggle (`product_form_live.ex`), delivery option field help, graph legend and summary (`fulfillments_live.ex`).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A free-delivery cart is charged per the chosen rule at 4, 5 and 6 km, covered by a test
- [ ] #2 Store and admin copy says the first 5 km are free, in en, fi and sv
- [ ] #3 The delivery admin graph shows the free-delivery fee curve under the chosen rule
<!-- AC:END -->
