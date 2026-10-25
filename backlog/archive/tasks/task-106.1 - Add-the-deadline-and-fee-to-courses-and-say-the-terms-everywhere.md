---
id: TASK-106.1
title: Add the deadline and fee to courses and say the terms everywhere
status: done
assignee: []
created_date: '2026-10-23 18:42'
updated_date: '2026-10-23 20:58'
labels: []
dependencies: []
parent_task_id: TASK-106
type: feature
ordinal: 227000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** One source for the terms keeps the course page, FAQ and emails from disagreeing.

Fields on the course and the course form, the generated sentence in en, fi and sv, used by the booking emails, course page and FAQ.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The course form edits the deadline and fee
- [x] #2 Existing courses read 7 days and 0%
- [x] #3 The course page, FAQ and booking emails show the generated sentence and never "we'll work something out"
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The FAQ isn't about one course, so it says each course's page states its terms rather than repeating a sentence.
<!-- SECTION:NOTES:END -->
