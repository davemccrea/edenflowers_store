---
id: TASK-49
title: Retry failed subscription starts every 15 minutes
status: ready-for-agent
assignee: []
created_date: '2026-10-18 18:22'
labels:
  - spec
  - developers
  - quick
dependencies: []
priority: low
type: chore
ordinal: 114000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Placing an order already starts its subscription straight away (`AshOban.run_trigger` in `order.ex`). The every-minute schedule only retries starts that failed, so running it every minute is wasted queries.

Change the `start_subscription` trigger's `scheduler_cron` to `"*/15 * * * *"` and update its comment.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 start_subscription's scheduler runs every 15 minutes
<!-- AC:END -->
