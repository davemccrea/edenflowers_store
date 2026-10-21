---
id: TASK-82
title: Let customers choose their own price for a bouquet
status: needs-triage
assignee: []
created_date: '2026-10-21 14:36'
labels:
  - spec
  - customers
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 167000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Let a customer pay more than a size's price for a bouquet, so they can go all out, like a 120 € Weekly Bouquet.

**Why:** Some customers want a bigger, showier bouquet than the largest size offers, and today they can't buy one online. Letting them name their price turns that wish into a larger order instead of a phone call or a lost sale.

### Problem

Every size (`ProductVariant`) has one fixed price. A customer who wants to spend more than the largest size has to contact Jennie, who then enters it as a Custom Order with a price she types in.

### Open questions

1. **Which products allow it?** Every bouquet, or an opt-in flag per product (Weekly Bouquet, florist's choice) set in the admin?
2. **How is it chosen?** A free amount field, or extra steps above the largest size (e.g. 100 €, 120 €, 150 €)?
3. **Bounds:** the minimum is presumably the cheapest (or chosen) size's price. Is there a maximum, and a step (whole euros)?
4. **Subscriptions:** can a Subscription carry a chosen price on every delivery, and how does that combine with the Subscriber Discount (TASK-3)?
5. **What Jennie sees:** the order line should show the chosen price clearly so she knows how big to make it. Does she need a guide to what an amount buys?
6. **Name:** add a term to `CONTEXT.md` once settled.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A customer can buy a bouquet at a price they choose, at or above its minimum, from the product page
- [ ] #2 The chosen price is what's charged, and shows on the cart, checkout, confirmation email and the admin order
- [ ] #3 A price below the minimum is rejected by the order line's action, not only in the form
<!-- AC:END -->
