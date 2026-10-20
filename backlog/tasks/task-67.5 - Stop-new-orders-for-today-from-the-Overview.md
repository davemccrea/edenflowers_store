---
id: TASK-67.5
title: Stop new orders for today from the Overview
status: done
assignee: []
created_date: '2026-10-20 06:52'
updated_date: '2026-10-20 16:58'
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
- [x] #1 Turning it off makes today unavailable at checkout, and on reopens it
- [x] #2 Tomorrow is unaffected
- [x] #3 The existing suite passes
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Each day section on Overview (Today, Tomorrow) has a Stop orders / Reopen orders button using ShopCalendar toggle_date. Shown only while the day is bookable or closed by a one-day override; same_day is never touched.
<!-- SECTION:FINAL_SUMMARY:END -->
