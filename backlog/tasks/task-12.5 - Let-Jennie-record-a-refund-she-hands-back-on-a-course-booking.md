---
id: TASK-12.5
title: Let Jennie record a refund she hands back on a course booking
status: done
assignee: []
created_date: '2026-10-17 09:39'
updated_date: '2026-10-19 20:30'
labels: []
dependencies:
  - TASK-12.2
parent_task_id: TASK-12
type: feature
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

Decision 4 of the spec for money handed back in person: a booking paid at the course is refunded in cash, MobilePay or on Zettle, and the Stripe refund button can't do that.

- A registration action records a negative in-person `Payment` with the method Jennie picks, on a confirmed or cancelled booking.
- It can't take the booking's in-person total below zero, the same rule as issue 04 for orders.
- The admin course page offers it on a booking that still holds in-person money and has a negative balance.
- Copy through gettext; clear fuzzy msgstrs in en, fi and sv.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Jennie can record an in-person refund on a booking, including a cancelled one
- [x] #2 A refund larger than the in-person money taken is refused
- [x] #3 The booking's balance reaches zero once the refund is recorded
<!-- AC:END -->
