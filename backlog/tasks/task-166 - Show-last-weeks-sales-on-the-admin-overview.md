---
id: TASK-166
title: Show last week's sales on the admin overview
status: ready-for-agent
assignee: []
created_date: '2026-11-01 16:34'
labels:
  - admin
  - quick
dependencies: []
priority: medium
type: feature
ordinal: 306000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The admin overview shows orders and revenue for the last full week (Mon-Sun, Helsinki) next to the week before.

**Why:** The relaunch plan's metric is orders per week, checked every Monday (TASK-162.5). Umami sees only online orders, so the weekly count, which includes Custom Orders, has to come from the shop's own data.

Decisions (grilled 2026-11-01, trimmed in a Ponytail review):
- One row in the existing sales widget on the overview, e.g. 'Last week: N orders, X EUR (week before: M, Y EUR)'.
- Reuses Orders.sales_summary!/3 with the two week ranges. No new module.
- Not now: reading sources from Umami's API. Umami's own dashboard covers that. Add it if Jennie starts doing the weekly check herself.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The overview shows orders and revenue for last week and the week before, Custom Orders included
- [ ] #2 Weeks run Monday to Sunday in Helsinki time
<!-- AC:END -->
