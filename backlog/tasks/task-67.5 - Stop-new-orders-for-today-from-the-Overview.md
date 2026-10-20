---
id: TASK-67.5
title: Stop new orders for today from the Overview
status: ready-for-agent
assignee: []
created_date: '2026-10-20 06:52'
updated_date: '2026-10-20 06:52'
labels: []
dependencies:
  - TASK-67.1
parent_task_id: TASK-67
type: feature
ordinal: 146000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** When Jennie is swamped or ill she needs to stop same-day orders in one tap, without finding today on the Fulfillments calendar.

### What to build

- A switch in the Today section, shown while today is open: "Taking orders for today". Turning it off closes today with ShopCalendar's `toggle_date`, so it resets by itself tomorrow; turning it back on reopens today.
- It never touches the `same_day` setting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Turning it off makes today unavailable at checkout, and on reopens it
- [ ] #2 Tomorrow is unaffected
- [ ] #3 The existing suite passes
<!-- AC:END -->
