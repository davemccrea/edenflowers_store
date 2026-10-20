---
id: TASK-67.3
title: Summarise the week ahead on the Overview
status: ready-for-agent
assignee: []
created_date: '2026-10-20 06:52'
updated_date: '2026-10-20 06:52'
labels: []
dependencies:
  - TASK-67.1
parent_task_id: TASK-67
type: feature
ordinal: 144000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie buys from the wholesaler anywhere from a day to a week ahead and needs to see the coming load at a glance without scrolling through every order.

### What to build

- A row of the next 7 days after tomorrow, each with its open order count, linking to the Orders list filtered to that date (check Cinder's `fulfillment_date` filter can be set from the URL).
- A make list under it: product and size totals across today through 7 days ahead, cards left out, largest first. Totals come from a domain action, not the LiveView.
- Days the shop calendar has closed show as closed rather than 0.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Per-day counts link to that day's orders
- [ ] #2 The make list totals products and sizes correctly, without cards or cancelled orders
- [ ] #3 The existing suite passes
<!-- AC:END -->
