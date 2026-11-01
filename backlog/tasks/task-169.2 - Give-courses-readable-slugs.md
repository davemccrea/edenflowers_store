---
id: TASK-169.2
title: Give courses readable slugs
status: ready-for-agent
assignee: []
created_date: '2026-11-01 21:15'
labels: []
dependencies:
  - TASK-169.1
parent_task_id: TASK-169
type: feature
ordinal: 316000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Course links Jennie shares should read like the course, not a UUID.

Follow the decisions in TASK-169 and reuse the slugify function from TASK-169.1. `bookings` and `pay` are reserved slugs. Repeat runs of the same workshop get -2 unless Jennie edits the slug.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A course is reachable at /:language/courses/:slug and /courses/:slug redirects as today
- [ ] #2 UUID course URLs and earlier slugs permanently redirect to the current slug URL
- [ ] #3 Earlier slugs and bookings/pay are reserved; a clashing generated slug gets -2, -3, …
- [ ] #4 The course form has a Link field with URL preview that fills from the name on new courses and normalises what Jennie types
- [ ] #5 Renaming a course leaves its slug unchanged
- [ ] #6 Every course URL the app builds (share drawer, emails, sitemap, admin links) uses the slug
- [ ] #7 Release.migrate backfills slugs for existing courses
<!-- AC:END -->
