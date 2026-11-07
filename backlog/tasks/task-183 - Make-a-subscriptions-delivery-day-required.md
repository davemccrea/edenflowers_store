---
id: TASK-183
title: Make a subscription's delivery day required
status: done
assignee: []
created_date: '2026-11-07 14:20'
updated_date: '2026-11-07 17:01'
labels:
  - developers
dependencies: []
priority: low
type: chore
ordinal: 348000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** a subscription's delivery_day is nullable only so that subscriptions started before it existed could be filled in on deploy. Once production has one for every subscription, making it required lets the database guarantee it, and the backfill can go.

Ships as a second deploy, after the deploy that adds delivery_day has run Release.migrate in production. Check first that no subscription has a nil delivery_day.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 delivery_day is allow_nil? false on Subscription, with a generated migration
- [x] #2 The subscriptions_next_date_on_delivery_day check drops its IS NULL escape
- [x] #3 The delivery_day backfill in Release.migrate is removed
<!-- AC:END -->
