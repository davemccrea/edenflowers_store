---
id: TASK-67.5
title: Stop new orders for a day from the Overview
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
**Why:** When Jennie is swamped or ill she needs to stop new orders for today or tomorrow in one tap, without finding the day on the Fulfillments calendar.

### What to build

- A "Stop orders" button in the Today and Tomorrow sections, shown while customers can book that day. It closes just that day with ShopCalendar's `toggle_date`, so nothing carries over to later days.
- Once closed, the section says "Closed to new orders." and the button becomes "Reopen orders", which reopens the day.
- No button on a day the weekday rules, the `same_day` setting or today's order deadline already close.
- It never touches the `same_day` setting.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Stopping a day makes it unavailable at checkout, and reopening makes it available again
- [x] #2 Closing one day leaves the other days as they were
- [x] #3 The existing suite passes
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Each day section on Overview (Today, Tomorrow) has a Stop orders / Reopen orders button using ShopCalendar toggle_date. Shown only while the day is bookable or closed by a one-day override; same_day is never touched.
<!-- SECTION:FINAL_SUMMARY:END -->
