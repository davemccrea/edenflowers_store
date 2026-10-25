---
id: TASK-121.3
title: Move course booking rules into calculations
status: done
assignee: []
created_date: '2026-10-25 10:08'
updated_date: '2026-10-25 13:11'
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
- [x] #1 The cancel drawer prefills from refund_on_cancelling and :cancel without a refund argument refunds that amount
- [x] #2 The account timeline sorts course bookings by CourseRegistration.upcoming?
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Review follow-up: the booking confirmation page shows payment pending until the paid broadcast arrives, and cancellation instructions read upcoming?. Updated the old pending-confirmation tests and the glossary's obsolete seat-hold model.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-25 10:43

---

Ready to pick up in a fresh session: TASK-120 (its dependency) is done. Also consider while there: CourseBookingDrawers.to_collect?/to_refund? derive settlement state in the web and could be Payable calculations.

---
<!-- COMMENTS:END -->
