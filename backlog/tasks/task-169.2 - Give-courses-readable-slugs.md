---
id: TASK-169.2
title: Give courses readable slugs
status: done
assignee: []
created_date: '2026-11-01 21:15'
updated_date: '2026-11-02 11:21'
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
- [x] #1 A course is reachable at /:language/courses/:slug and /courses/:slug redirects as today
- [x] #2 UUID course URLs and earlier slugs permanently redirect to the current slug URL
- [x] #3 Earlier slugs and bookings/pay are reserved; a clashing generated slug gets -2, -3, …
- [x] #4 The course form has a Link field with URL preview that fills from the name on new courses and normalises what Jennie types
- [x] #5 Renaming a course leaves its slug unchanged
- [x] #6 Every course URL the app builds (share drawer, emails, sitemap, admin links) uses the slug
- [x] #7 Release.migrate backfills slugs for existing courses
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
No reserved slugs after all: /courses/bookings/:id and /courses/pay/:token have one more path segment than /courses/:slug, so a course slug can't collide with them. Product and course share Edenflowers.Slug.SetSlug, Edenflowers.Slug.CurrentSlug, Plugs.RedirectOldLinks and Admin.SlugField; each keeps its own former-slug resource. Course's default create/update became explicit actions to carry the slug change. Edited-slug clash message is now 'is already taken' for both.
<!-- SECTION:NOTES:END -->
