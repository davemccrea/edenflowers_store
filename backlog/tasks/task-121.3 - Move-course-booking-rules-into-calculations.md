---
id: TASK-121.3
title: Move course booking rules into calculations
status: ready-for-agent
assignee: []
created_date: '2026-10-25 10:08'
labels: []
dependencies:
  - TASK-120
parent_task_id: TASK-121
type: refactor
ordinal: 243000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The cancel drawer works out a booking's refund from the course's terms in the web layer, and the account timeline calls a course upcoming by date alone.

Add refund_on_cancelling to Payable (an order refunds all it holds; a booking applies its course's cancellation terms) and default :cancel's refund to it. Course.refund_on_cancelling/4 goes. The account timeline uses CourseRegistration.upcoming?.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The cancel drawer prefills from refund_on_cancelling and :cancel without a refund argument refunds that amount
- [ ] #2 The account timeline sorts course bookings by CourseRegistration.upcoming?
<!-- AC:END -->
