---
id: TASK-164
title: Apply a promo code from a link
status: done
assignee: []
created_date: '2026-11-01 16:22'
updated_date: '2026-11-05 11:25'
labels:
  - customers
dependencies: []
priority: medium
type: feature
ordinal: 304000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Opening a site link with ?code=… puts that promo code on the visitor's cart, so nobody has to type it.

**Why:** The 'pass it on' cards (TASK-162.3) print a one-use code and a QR code. If the QR applies the code itself, the gift recipient goes straight from the card to choosing flowers. The same links work in Instagram posts and emails.

Decisions (grilled 2026-11-01 with TASK-162.3):
- Any storefront URL accepts ?code=. The root redirect already keeps the query string, so edenflowers.fi/?code=AB12CD reaches the localised page with it.
- The code is held for the visitor and applied to the cart as soon as there is one, through the existing apply-promotion action and its rules (dates, usage limit).
- If the cart already has a code, the link's code replaces it: opening the link is the customer's latest choice (changed 2026-11-13; before, the cart's code was kept, as for the newsletter code at checkout, TASK-158). An unusable link code leaves the cart's code alone.
- An unknown or used-up code does nothing beyond the usual promo feedback at checkout. No error page.
- Umami's 'Promo code applied' event fires as usual, and the link's UTM tags still count.

Open for implementation: where the code is held before a cart exists (session), and whether the visitor sees a short confirmation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Opening a storefront link with ?code= applies a usable code to the visitor's cart
- [x] #2 A usable code replaces a code already on the cart
- [x] #3 An unusable code fails quietly, with no error page
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented 2026-11-05: any storefront request with ?code= opens the browser's cart (if needed) and puts a usable code on it (Plugs.ApplyLinkPromotion -> Order :open_cart_with_code), rather than holding it in the session, which LiveViews can't clear. The minimum cart total isn't checked on a link: the cart says 'spend at least' until it's reached. An empty cart holding a code is purged after 30 days instead of 1. A flash confirms the code; Umami's 'Promo code applied' fires once per browser per code from PutOrder.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-05 07:56

---

Closed by David on 2026-11-05 without implementing.

---

author: @claude
created: 2026-11-05 08:40

---

Reopened 2026-11-05: closing it was accidental. The pass-it-on card QRs carry the code (TASK-165).

---
<!-- COMMENTS:END -->
