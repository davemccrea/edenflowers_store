---
id: TASK-89
title: Get an email when the shop goes down
status: ready-for-agent
assignee: []
created_date: '2026-10-21 19:46'
updated_date: '2026-10-21 19:51'
labels:
  - spec
  - admin
  - customers
dependencies: []
priority: medium
type: chore
ordinal: 183000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Watch production from an external service and email David when the shop stops answering.

**Why:** Nothing tells us today when the site or the server is down, so a dead checkout can lose orders for hours until a customer complains.

Decisions:
- Better Stack free tier checks production `/health` every 3 minutes and confirms a failure from a second region before alerting.
- Alerts go to David by email only, with a recovery email when the site is back. Jennie isn't alerted: she can't fix an outage.
- Production only. Staging goes down on every redeploy and reseed.
- `/health` checks the database only. A Stripe or email outage isn't the shop being down, and Oban job failures already reach ErrorTracker.
- Self-hosting Uptime Kuma on the same server is out: it dies with the thing it watches.

The nightly backup cron already pings healthchecks.io (TASK-81.2); that covers jobs that stop running, not the site being down.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An external service checks production at least every 5 minutes
- [ ] #2 The check fails when the app or database is down, not only when the server is unreachable
- [ ] #3 A failed check sends an email to the agreed people
<!-- AC:END -->
