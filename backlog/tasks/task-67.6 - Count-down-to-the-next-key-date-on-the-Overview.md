---
id: TASK-67.6
title: Count down to the next key date on the Overview
status: ready-for-agent
assignee: []
created_date: '2026-10-20 06:52'
updated_date: '2026-10-20 06:52'
labels: []
dependencies:
  - TASK-67.1
parent_task_id: TASK-67
type: feature
ordinal: 147000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Mother's Day and Valentine's Day are the shop's peaks; seeing one coming, with how many orders already fall that week, prompts buying and capacity decisions in time.

### What to build

- When a date from `Fulfillment.KeyDates` is within 30 days, a line saying which, in how many days, and how many open orders fall in the 7 days up to it.
- Reuse KeyDates and its labels. Adding All Saints' Day, Christmas or graduations means artwork in `KeyDateIcon` for the checkout calendar too, so it's a separate decision.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The next key date within 30 days shows with its countdown and order count
- [ ] #2 Nothing shows when none is within 30 days
- [ ] #3 The existing suite passes
<!-- AC:END -->
