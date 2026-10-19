---
id: TASK-61.2
title: >-
  Record a failed online receipt or order details email instead of retrying it
  forever or dropping it
status: ready-for-agent
assignee: []
created_date: '2026-10-19 07:59'
updated_date: '2026-10-19 07:59'
labels: []
dependencies:
  - TASK-61.1
parent_task_id: TASK-61
type: bug
ordinal: 129000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** an online order's receipt that can't send is retried every 10 minutes indefinitely: `send_confirmation_email` has a recovery scheduler and no `on_error`, and AshOban's docs say the scheduler may reschedule once attempts run out. A custom order's details email gives up silently after 20 attempts. Either way Jennie never learns the customer has nothing.

Apply TASK-61's decisions, following the shape TASK-61.1 lands:

- **Online receipt** (`Order` trigger `send_confirmation_email`, queued by `Payments.Changes.ScheduleConfirmationEmail`): drop the scheduler and its `where`, `max_attempts 3`, `on_error` sets `receipt_email_failed_at`, which a successful send (this action or `email_receipt`) clears. Log "Receipt failed". Jennie's existing "Resend receipt" menu item is the way to send it again.
- **Order details** (`send_order_details_email`): `max_attempts 3`, `on_error` sets `details_email_failed_at`, cleared on success. Log "Order details failed". The existing "Resend order details" item sends it again.
- Publish both failures for open order pages, as TASK-61.1 does, and show a warning on the order page while either is set.

Course bookings' confirmation email is TASK-61.3.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An online receipt or order details email that fails its last attempt records the failure and stops; nothing requeues it
- [ ] #2 The order log shows the failure, and a later successful send (queued or Jennie's resend) clears it
- [ ] #3 An open order page shows the failure without polling
- [ ] #4 Tests cover the final failure through on_error, clearing on resend, and that no scheduler is left
<!-- AC:END -->
