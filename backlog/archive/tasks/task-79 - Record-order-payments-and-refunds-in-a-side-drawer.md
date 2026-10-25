---
id: TASK-79
title: Record order payments and refunds in a side drawer
status: done
assignee: []
created_date: '2026-10-20 18:46'
updated_date: '2026-10-20 18:55'
labels:
  - spec
  - admin
dependencies:
  - TASK-60
priority: medium
type: feature
ordinal: 161000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie records an order's payment, refund or goodwill refund in the same side drawer the Courses page uses, instead of forms that unfold on the order page.

**Why:** After TASK-60, recording money worked one way for bookings and another for orders. One drawer pattern on both pages means Jennie learns it once, and the order page no longer shifts when a form opens.

### What's built

- The balance panel keeps the amount and the payment-link buttons, plus one Record payment / Record refund button that opens the drawer.
- The drawer shows the customer, order reference, total, paid and balance, then Refund with Stripe and/or the record form, worded like the Courses drawer.
- The menu's Refund opens the goodwill form in the same drawer.
- On success the drawer closes; on an error it stays open with the message and what Jennie typed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Record payment / Record refund on the order page opens a drawer with the order's money context
- [x] #2 Refund with Stripe and recording a refund outside Stripe are both in the drawer and clearly distinguished
- [x] #3 The menu's Refund opens the goodwill refund in the drawer
- [x] #4 Errors keep the drawer open with the entered values
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
balance_panel now only summarises and opens the drawer; its form moved to record_payment_form in Admin.Components. Order page settlement_drawer mirrors CoursesLive's. Awaiting David's UI review before commit.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-20 18:55

---

Shipped in 3d0fd5ad, alongside TASK-60.

---
<!-- COMMENTS:END -->
