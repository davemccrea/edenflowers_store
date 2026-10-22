---
id: TASK-92.3
title: 'Cancel a course booking from the admin with a refund, reason and email'
status: ready-for-agent
assignee: []
created_date: '2026-10-22 14:39'
labels: []
dependencies:
  - TASK-92.1
  - TASK-92.2
parent_task_id: TASK-92
type: feature
ordinal: 199000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The booking half of TASK-92, so cancelling works the same for bookings as for orders and the customer is told.

- `CourseRegistration.cancel` takes the same `refund_amount`, `cancellation_reason` and `email_customer?` arguments and behaves as `Order.cancel` does after TASK-92.2.
- New `booking_cancelled` email: the booking cancelled, the reason, what was refunded or will be returned. BCC Jennie.
- Courses page: Cancel opens the same drawer. History shows the reason and whether the customer was emailed.
- Copy through gettext; clear fuzzy msgstrs in en, fi and sv.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Cancelling a booking refunds the chosen amount through Stripe, keeps the rest and leaves a 0 balance
- [ ] #2 A refused Stripe refund leaves the booking confirmed and queues no email
- [ ] #3 The customer gets a booking_cancelled email with the reason and refund, unless unticked
- [ ] #4 The history shows the reason and whether the customer was emailed
<!-- AC:END -->
