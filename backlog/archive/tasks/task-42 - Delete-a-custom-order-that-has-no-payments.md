---
id: TASK-42
title: Delete a custom order that has no payments
status: done
assignee: []
created_date: '2026-10-18 18:22'
updated_date: '2026-10-19 09:44'
labels:
  - spec
  - admin
dependencies: []
priority: low
type: feature
ordinal: 103000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Test orders and orders added by mistake clutter Jennie's lists and reports, and cancelling one leaves it there for good.

Add a destroy action for custom orders with no recorded payments, and a Delete button (with confirmation) on the order page only for those. Return its stock as cancelling does. Any order with a payment, or any online order, is cancelled as today, so the accounts stay whole.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A custom order with no payments can be deleted from its page after confirming
- [x] #2 Its stock is returned
- [x] #3 Online orders and orders with a payment have no Delete button and the action refuses them
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-19 09:44

---

Delete now cancels the PaymentIntent before the order goes and refuses while a payment is under way (processing or succeeded), so a payment always has an order to land on. Found in the 2026-10-18 commit review.

---
<!-- COMMENTS:END -->
