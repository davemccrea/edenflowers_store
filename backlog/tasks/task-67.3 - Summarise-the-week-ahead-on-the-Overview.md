---
id: TASK-67.3
title: Summarise the week ahead on the Overview
status: done
assignee: []
created_date: '2026-10-20 06:52'
updated_date: '2026-10-21 13:49'
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
- [x] #1 Tapping a day shows that day's orders in place
- [x] #2 Closed days are marked on the strip
- [x] #3 The existing suite passes
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Today, Tomorrow and the week ahead merged into one card: a strip of 9 days (today to 8 days out) with open order counts and closed days marked. Tapping a day patches ?day= and lists its deliveries and pickups in place. Stop/Reopen orders shows on today only. The make list was dropped: not worth the space.
<!-- SECTION:FINAL_SUMMARY:END -->
