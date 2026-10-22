---
id: TASK-98.1
title: Release an unpaid seat hold with its own action
status: ready-for-agent
assignee: []
created_date: '2026-10-22 19:47'
labels: []
dependencies: []
parent_task_id: TASK-98
type: refactor
ordinal: 205000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** `:cancel` also releases holds the customer never paid for, so a hold release runs the refund and email steps as a no-op and the cancelled email needs a special case to skip it.

Add `CourseRegistration :release_hold`, pending only, used by the system actor where a hold is released today.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Seat holds are released through :release_hold, only on pending bookings
- [ ] #2 SendCancelledEmail no longer skips unconfirmed bookings
<!-- AC:END -->
