---
id: TASK-141.2
title: Say when the shop is closed for a holiday
status: done
assignee: []
created_date: '2026-10-28 20:53'
updated_date: '2026-10-29 03:17'
labels:
  - wontfix
dependencies: []
parent_task_id: TASK-141
type: feature
ordinal: 276000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** A visitor during a holiday closure should read that the shop is closed and until when, not just a far-off next delivery date that looks like a mistake.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 When disabled dates push the next open day out, the bar reads "Closed until <weekday date>"
- [ ] #2 Normal weekly days off still show the order-status line
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-29 03:17

---

Built, then dropped on 2026-10-29: "Closed" suggested Jennie couldn't be reached, when customers can still order during a holiday for when she's back. The plain "Next delivery or pickup is <weekday date>" line already says that.

---
<!-- COMMENTS:END -->
