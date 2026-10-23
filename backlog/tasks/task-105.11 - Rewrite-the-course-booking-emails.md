---
id: TASK-105.11
title: Rewrite the course booking emails
status: ready-for-agent
assignee: []
created_date: '2026-10-23 18:42'
labels: []
dependencies:
  - TASK-105.2
  - TASK-105.4
  - TASK-105.5
parent_task_id: TASK-105
type: feature
ordinal: 224000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The course emails should follow the same rules as the order emails, and the after-course versions are covered by Payment received and the reminder.

Booking confirmed: subject "You're booked on <course>, <date>", place or places confirmed, when and where, receipt attached, the course's cancellation terms, "See you there". Course payment link: before the course only, subject with the course and date, "I've kept you a place", Jennie's message, amount and "You can pay online here:", when, where and terms. After the course, a booking awaiting payment gets the payment reminder instead.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Booking subjects include the course date
- [ ] #2 No course email has an after-the-course version
- [ ] #3 Previews on the admin Emails page cover every version, and the new copy is translated in en, fi and sv
<!-- AC:END -->
