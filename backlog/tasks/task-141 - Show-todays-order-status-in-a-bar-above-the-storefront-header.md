---
id: TASK-141
title: Storefront notice bar above the header
status: done
assignee: []
created_date: '2026-10-28 20:35'
updated_date: '2026-10-29 03:27'
labels:
  - customers
  - spec
dependencies: []
priority: medium
type: feature
ordinal: 274000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A bar above the header on every storefront page tells visitors whether they can still get flowers today, or else the next delivery or pickup day, and links to the store. The homepage's Delivery and pickup section opens with the same line.

**Why:** Visitors ask "can I still get flowers today?" on product pages and in the cart, not only on the homepage, where the answer was buried as "Next available day" (review note #12).

Decisions (grilled 2026-10-28, revised 2026-10-29):
- Bar above the header on all pages in the :public live session; admin and payment links unaffected. Not dismissible. Off-white with a hairline and semibold text like the header; see-through with white shadowed text over a page's opening photo. The whole bar links to the store, with a right arrow.
- "Order by 14:00 for delivery or pickup today", else the next open day ("tomorrow" when it is). No open day in 60 days -> no bar. Rechecks every minute. The line comes from Fulfillment.Availability.order_status/2.
- Dropped after building: Jennie's own notice and promotions (TASK-141.3, 141.4; rarely used, promotions advertised off-site) and a "Closed until" holiday line (TASK-141.2; customers can still order during a holiday).
- Checking delivery to an address is TASK-142.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-29 02:42

---

2026-10-29: Considered letting Jennie reorder the bar's lines. Kept the fixed order (notice > closure > promotion > order status): her notice and the promotion's Show in bar toggle already decide what shows, and order status is the fallback. Only closure vs promotion is fixed; revisit if she asks for a promotion during a closure.

---
<!-- COMMENTS:END -->
