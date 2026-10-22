---
id: TASK-93
title: Email the customer when a seat is removed from their group booking
status: needs-triage
assignee: []
created_date: '2026-10-22 14:39'
labels:
  - spec
  - customers
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
