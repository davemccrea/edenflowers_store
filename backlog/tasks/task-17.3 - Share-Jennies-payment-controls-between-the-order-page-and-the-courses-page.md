---
id: TASK-17.3
title: Share Jennie's payment controls between the order page and the courses page
status: needs-triage
assignee: []
created_date: '2026-10-18 03:08'
labels: []
dependencies:
  - TASK-17.1
parent_task_id: TASK-17
type: refactor
ordinal: 50000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

`Admin.OrderDetailLive` and `Admin.CoursesLive` each handle `record_payment`, `undo_payment`, `refund_with_stripe`, `open_payment_link` and `email_payment_link` against a payable, with their own flash messages and error handling. The order page also renders the payments list, money rows and payment-link buttons, which the courses page shows its own way for each booking.

### The idea

The handlers call `Payable` actions that share names (after `TASK-17.1`), so they can live once: a LiveComponent for "the money on this record" (payments list, record and undo, refund, payment link), mounted on the order page and in each booking's row or drawer. Each page keeps its own layout around it.

### To decide

- The courses page manages many bookings on one page, where the order page has one record. Check whether one component reads well in both, or only the handlers should be shared.
<!-- SECTION:DESCRIPTION:END -->
