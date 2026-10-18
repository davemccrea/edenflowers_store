---
id: TASK-32
title: >-
  Show what's paid and left to pay on a payment-link page only once something is
  paid
status: ready-for-agent
assignee: []
created_date: '2026-10-18 18:22'
labels:
  - spec
  - customers
  - quick
dependencies: []
priority: low
type: feature
ordinal: 87000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** On a fresh payment link, "Left to pay" repeats the total and makes the customer wonder what they missed. It only means something after a part payment.

`checkout/pay_live.ex` and `courses/course_pay_live.ex` show Total, Paid and Left to pay. Show Paid and Left to pay only when `amount_paid` is positive. Otherwise show the amount due alone.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A payment link with nothing paid shows only the amount due, on both the order and the booking page
- [ ] #2 A payment link after a part payment shows the total, what's paid and what's left to pay
<!-- AC:END -->
