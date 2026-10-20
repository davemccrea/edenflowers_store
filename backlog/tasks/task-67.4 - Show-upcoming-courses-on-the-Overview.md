---
id: TASK-67.4
title: Show upcoming courses on the Overview
status: ready-for-agent
assignee: []
created_date: '2026-10-20 06:52'
updated_date: '2026-10-20 06:52'
labels: []
dependencies:
  - TASK-67.1
parent_task_id: TASK-67
type: feature
ordinal: 145000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie prepares materials for each course, so she needs to see seats booked a couple of weeks ahead.

### What to build

- A section listing courses in the next 14 days: name, date and time, `seats_taken` of `total_places`, linking to the course.
- A course on today's date also shows as one line in the Today section.
- Hidden when there are none. Refreshes on `admin:bookings`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Courses in the next 14 days show with seats booked
- [ ] #2 Today's course appears under Today
- [ ] #3 The existing suite passes
<!-- AC:END -->
