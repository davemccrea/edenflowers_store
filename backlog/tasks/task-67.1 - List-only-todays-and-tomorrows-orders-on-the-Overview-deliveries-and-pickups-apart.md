---
id: TASK-67.1
title: >-
  List only today's and tomorrow's orders on the Overview, deliveries and
  pickups apart
status: ready-for-agent
assignee: []
created_date: '2026-10-20 06:52'
labels: []
dependencies: []
parent_task_id: TASK-67
type: feature
ordinal: 142000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** These are the orders Jennie is making now; everything further out is noise on a phone screen.

### What to build

- Replace the Upcoming orders widget with a Today section and a Tomorrow section, each keeping the current order row.
- Within each day, deliveries first (by time window, then distance) and pickups after, under their own small headings.
- An empty day says so in one line rather than disappearing, so "nothing today" is a visible answer.
- Overdue orders leave this list; they move to Needs attention (TASK-67.2).
- Lay the page out in the spec's order. Phone: one column. Desktop: Today and Tomorrow in the main column, the rest beside or below; check it at 390px and 1280px.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Only today's and tomorrow's open orders are listed
- [ ] #2 Deliveries and pickups are grouped apart within each day
- [ ] #3 The layout reads well at phone and desktop widths
- [ ] #4 The existing suite passes
<!-- AC:END -->
