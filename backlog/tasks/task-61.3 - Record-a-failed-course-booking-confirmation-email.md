---
id: TASK-61.3
title: 'Queue the course booking confirmation once, with no scheduler or skip flag'
status: done
assignee: []
created_date: '2026-10-19 07:59'
updated_date: '2026-10-19 20:12'
labels: []
dependencies:
  - TASK-61.1
parent_task_id: TASK-61
type: bug
ordinal: 130000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** a course booking's confirmation that can't send was retried every 10 minutes indefinitely, as online receipts were (TASK-61.2), so the attendee never got it and nobody heard.

Drop `CourseRegistration`'s `send_confirmation_email` scheduler and its `where`, and set `max_attempts 3`. Remove `skip_confirmation_email`, which only stopped the scheduler: `email_customer?` now only decides whether the job is queued.

### Decided
No `confirmation_email_failed_at`. Bookings have no history and the courses page has nowhere for a failure to show, so a failed confirmation takes the developer path from ADR 0005: ErrorTracker alerts, and the job is retried from `/oban`.

The booking row's actions menu gets "Email confirmation" / "Resend confirmation" (after `confirmation_emailed_at`), with a "Last sent" confirm like the payment link. It runs `email_receipt`, which sends while Jennie waits and flashes "Confirmation emailed." or "Could not email the confirmation."
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A booking's confirmation is queued once and stops after 3 failed attempts; no scheduler requeues it
- [x] #2 A booking Jennie adds without emailing queues no job, with no skip flag
- [x] #3 Jennie can email or resend a booking's confirmation from its actions menu, asked first, with the last send time once there is one
<!-- AC:END -->
