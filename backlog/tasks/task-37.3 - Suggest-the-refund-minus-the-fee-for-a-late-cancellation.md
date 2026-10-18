---
id: TASK-37.3
title: Suggest the refund minus the fee for a late cancellation
status: ready-for-agent
assignee: []
created_date: '2026-10-18 18:22'
labels: []
dependencies:
  - TASK-37.1
parent_task_id: TASK-37
type: feature
ordinal: 98000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie shouldn't have to work out the fee each time she refunds a late cancellation.

When Jennie refunds a booking less than 7 days before the course starts, the refund amount defaults to what's paid minus the course's `late_cancellation_fee` (never below 0). She can still change it. Earlier refunds default to the full amount as today.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A refund less than 7 days before the course defaults to the amount paid minus the fee
- [ ] #2 A refund 7 or more days before defaults to the full amount
- [ ] #3 Jennie can edit the suggested amount
<!-- AC:END -->
