---
id: TASK-164
title: Apply a promo code from a link
status: done
assignee: []
created_date: '2026-11-01 16:22'
updated_date: '2026-11-05 07:56'
labels:
  - customers
  - wontfix
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
- If the cart already has a code, it is kept and the link's code is not applied (the same rule as the newsletter code at checkout, TASK-158).
- An unknown or used-up code does nothing beyond the usual promo feedback at checkout. No error page.
- Umami's 'Promo code applied' event fires as usual, and the link's UTM tags still count.

Open for implementation: where the code is held before a cart exists (session), and whether the visitor sees a short confirmation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Opening a storefront link with ?code= applies a usable code to the visitor's cart
- [ ] #2 A code already on the cart is kept
- [ ] #3 An unusable code fails quietly, with no error page
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-05 07:56

---

Closed by David on 2026-11-05 without implementing.

---
<!-- COMMENTS:END -->
