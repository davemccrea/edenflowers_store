---
id: TASK-48.1
title: Add a private course with a quoted price
status: ready-for-agent
assignee: []
created_date: '2026-10-18 18:22'
labels: []
dependencies: []
parent_task_id: TASK-48
type: feature
ordinal: 112000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** A private course must never appear on the site, and its price is one quote for the group, not a price per seat.

Add `private?` to Course. A private course is left out of the store listing and course pages, has a total price instead of a price per seat, and has no late-cancellation fee by default. The courses page marks it "Private".
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Jennie can create a private course with a total price
- [ ] #2 A private course doesn't show on the website, and its page isn't reachable
- [ ] #3 The courses page marks it Private
<!-- AC:END -->
