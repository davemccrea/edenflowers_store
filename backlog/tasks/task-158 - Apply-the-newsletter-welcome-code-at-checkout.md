---
id: TASK-158
title: Apply the newsletter welcome code at checkout
status: done
assignee: []
created_date: '2026-10-31 20:23'
updated_date: '2026-10-31 20:23'
labels:
  - customers
  - spec
  - quick
dependencies: []
priority: medium
type: feature
ordinal: 293000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Ticking the newsletter box at checkout puts the subscriber's welcome code on the cart as soon as they move to the next step.

**Why:** Customers had to leave checkout and find the code in their inbox to get the discount the box promised, a step that loses discounts and sales mid-checkout.

Decisions (2026-10-31):
- The welcome code is created at signup (footer or checkout), not by the email job, so checkout can apply it at once.
- A code already on the cart is kept; the welcome code is still emailed for a later order.
- The welcome email still sends the code, so it isn't lost if the cart is abandoned.
- A lapsed subscriber's unused, still-usable code is applied too.
- Checkbox copy: "Subscribe to the newsletter and get 15% off this order." sv/fi drafted for Jennie to review.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Ticking the box and moving past step 1 shows the 15% welcome code on the cart
- [x] #2 A cart that already has a code keeps it, and the welcome code is still emailed
- [x] #3 The welcome email still includes the code
<!-- AC:END -->
