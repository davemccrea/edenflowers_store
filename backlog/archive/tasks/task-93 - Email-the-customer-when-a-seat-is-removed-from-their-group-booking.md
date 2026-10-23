---
id: TASK-93
title: Email the customer when a seat is removed from their group booking
status: done
assignee: []
created_date: '2026-10-22 14:39'
updated_date: '2026-10-23 18:42'
labels:
  - spec
  - customers
  - wontfix
dependencies: []
priority: low
type: feature
ordinal: 200000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Tell the customer when Jennie removes a seat from their group booking, and what's refunded.

**Why:** `remove_seat` is a partial cancel. After TASK-92 a full cancel emails the customer, but removing a seat still says nothing.

Open: should removing a seat use the same drawer (refund amount, reason, email), and does it need a `kept_amount` per seat?
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-23 18:42

---

Decided in the email grilling session on 2026-10-23: removing a seat sends no email of its own. The refund email, with Jennie's message, covers it when she refunds the seat.

---
<!-- COMMENTS:END -->
