---
id: TASK-36
title: Show which language a course is taught in
status: ready-for-agent
assignee: []
created_date: '2026-10-18 18:22'
labels:
  - spec
  - customers
  - admin
  - quick
dependencies: []
priority: low
type: feature
ordinal: 94000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Courses are taught in Swedish, now and then in English. Customers who don't speak Swedish need to know before they book.

Add `language` to Course, `:sv` or `:en`, default `:sv`. Jennie picks it on the course form. The course card and course page show it with the other course details.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 New courses default to Swedish and Jennie can switch to English on the course form
- [ ] #2 The course card and page show the language
<!-- AC:END -->
