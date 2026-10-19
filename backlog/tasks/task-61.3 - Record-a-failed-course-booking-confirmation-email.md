---
id: TASK-61.3
title: Record a failed course booking confirmation email
status: needs-triage
assignee: []
created_date: '2026-10-19 07:59'
labels: []
dependencies:
  - TASK-61.1
parent_task_id: TASK-61
type: bug
ordinal: 130000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** a course booking's confirmation that can't send is retried every 10 minutes indefinitely, as online receipts are (TASK-61.2), so the attendee never gets it and Jennie never hears.

The trigger fix is the same as TASK-61.2: drop `CourseRegistration`'s `send_confirmation_email` scheduler, `max_attempts 3`, `on_error` sets `confirmation_email_failed_at`, cleared on success. Its `skip_confirmation_email` exists for the scheduler and may go too; `email_receipt` currently clears it to send the confirmation again.

### Undecided
Bookings have no history log, so there is nowhere yet to show the failure, and the courses page has no "resend confirmation" control outside recording a settling payment. Decide where Jennie sees a failed booking email (a badge on the booking row is the cheapest) and how she sends it again, possibly alongside TASK-60's side drawer.
<!-- SECTION:DESCRIPTION:END -->
