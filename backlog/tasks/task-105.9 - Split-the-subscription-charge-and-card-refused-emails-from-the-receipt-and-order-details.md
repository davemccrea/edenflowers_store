---
id: TASK-105.9
title: >-
  Split the subscription charge and card-refused emails from the receipt and
  order details
status: ready-for-agent
assignee: []
created_date: '2026-10-23 18:42'
labels: []
dependencies: []
parent_task_id: TASK-105
type: feature
ordinal: 222000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** A full receipt every week or two is noise, and "your card was refused" is a different job from "here is your order".

Subscription delivery charged: matter-of-fact, signed Eden Flowers. Subject "Your flowers for <date>". "Your card was charged <amount> for your <product> delivery on <date>. Your receipt is attached." and the account link.

Subscription payment failed: Jennie's voice. Subject "Payment needed for your flowers on <date>". The payment didn't go through but the flowers still come (pickup: still ready to collect), the amount and "You can pay online here:" with the link, later deliveries on hold until it's paid, and update your card in your account.

Subscription set up: Jennie's voice, subject names the product, the facts block, "To pause, change or cancel, use your account at least 5 days before a delivery." The first order still gets the order receipt alongside it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each subscription charge sends Subscription delivery charged, not the order receipt
- [ ] #2 A refused card sends Subscription payment failed, not order details
- [ ] #3 Previews on the admin Emails page cover every version, and the new copy is translated in en, fi and sv
<!-- AC:END -->
