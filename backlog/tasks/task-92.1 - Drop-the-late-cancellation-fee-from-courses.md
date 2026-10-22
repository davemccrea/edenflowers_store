---
id: TASK-92.1
title: Drop the late-cancellation fee from courses
status: ready-for-agent
assignee: []
created_date: '2026-10-22 14:39'
labels: []
dependencies: []
parent_task_id: TASK-92
type: refactor
ordinal: 197000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie decides how much to refund on each late booking cancel (TASK-92 decision 7), so a fixed fee only promises customers something the app no longer does.

- Remove `late_cancellation_fee` from `Course` (regenerate the migration), its admin form field and `KeepLateCancellationFee`.
- Customer copy on the course page, booking page, confirmation email and FAQ becomes: cancel by replying to your confirmation email, at least 7 days before the course for a full refund, after that get in touch and we'll work something out. Through gettext; clear fuzzy msgstrs in en, fi and sv.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Course has no late_cancellation_fee and cancelling a booking keeps nothing on its own
- [ ] #2 Course page, booking page, confirmation email and FAQ show the new cancellation wording in en, fi and sv
<!-- AC:END -->
