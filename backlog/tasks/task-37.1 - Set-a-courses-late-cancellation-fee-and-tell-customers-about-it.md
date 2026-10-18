---
id: TASK-37.1
title: Set a course's late-cancellation fee and tell customers about it
status: done
assignee: []
created_date: '2026-10-18 18:22'
updated_date: '2026-10-18 19:42'
labels: []
dependencies: []
parent_task_id: TASK-37
type: feature
ordinal: 96000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The fee must be visible before booking and in the confirmation, or Jennie can't keep it.

Add `late_cancellation_fee` to Course, default 15.00, 0 meaning no fee. Jennie sets it on the course form. Update the three cancellation sentences (course page, booking form, confirmation email) to say: cancel at least 7 days before for a full refund, otherwise the fee is kept. With a 0 fee they keep today's wording.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A new course has a €15 late-cancellation fee that Jennie can change
- [x] #2 The course page, booking form and confirmation email name the course's fee
- [x] #3 A course with a 0 fee shows today's full-refund wording
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Course.late_cancellation_fee (decimal, default 15.00, min 0), on the admin course form. Existing courses get 15.00 from the migration default. Course page, booking page and paid confirmation email name the fee when positive; a 0 fee keeps the old sentence. The pay-at-course email branches never promised a refund, so they're unchanged. fi/sv translations added.
<!-- SECTION:NOTES:END -->
