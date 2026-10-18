---
id: TASK-37.1
title: Set a course's late-cancellation fee and tell customers about it
status: ready-for-agent
assignee: []
created_date: '2026-10-18 18:22'
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
- [ ] #1 A new course has a €15 late-cancellation fee that Jennie can change
- [ ] #2 The course page, booking form and confirmation email name the course's fee
- [ ] #3 A course with a 0 fee shows today's full-refund wording
<!-- AC:END -->
