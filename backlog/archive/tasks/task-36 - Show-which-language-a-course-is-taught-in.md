---
id: TASK-36
title: Show which language a course is taught in
status: done
assignee: []
created_date: '2026-10-18 18:22'
updated_date: '2026-10-19 10:20'
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

Add `language` to Course, `:sv`, `:fi` or `:en`, default `:sv`. Jennie picks it on the course form. The course card and course page show it with the other course details.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 New courses default to Swedish and Jennie can switch to Finnish or English on the course form
- [x] #2 The course card and page show the language
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-19 10:20

---

Finnish added as a choice (4041c55b): no course is taught in Finnish yet, but one may be.

---
<!-- COMMENTS:END -->
