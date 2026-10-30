---
id: TASK-147.2
title: Load the Umami tracker on shop pages
status: done
assignee: []
created_date: '2026-10-30 17:41'
updated_date: '2026-10-30 17:56'
labels: []
dependencies: []
parent_task_id: TASK-147
type: feature
ordinal: 283000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Page views and referrers are the base of every report. Script tag in the root layout when UMAMI_WEBSITE_ID is set, skipped on /admin and for admin users; UMAMI_WEBSITE_ID passed through compose.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Script loads on shop pages in prod
- [x] #2 Script is absent on /admin, for admin users, and when UMAMI_WEBSITE_ID is unset
<!-- AC:END -->
