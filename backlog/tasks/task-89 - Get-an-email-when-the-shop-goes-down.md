---
id: TASK-89
title: Get an email when the shop goes down
status: ready-for-human
assignee: []
created_date: '2026-10-21 19:46'
updated_date: '2026-10-22 04:41'
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

Once TASK-81.2 lands, the nightly backup cron pings healthchecks.io; that covers jobs that stop running, not the site being down.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An external service checks production at least every 5 minutes
- [x] #2 The check fails when the app or database is down, not only when the server is unreachable
- [ ] #3 A failed check sends an email to the agreed people
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Added GET /health (EdenflowersWeb.HealthController): runs SELECT 1 against the Repo and answers 200 "ok" with cache-control: no-store; a down database raises, so the check gets a 500. Lives outside the :browser pipeline, so maintenance mode doesn't redirect it.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-22 04:41

---

Code is in. Left for David, once /health is deployed to production: create a Better Stack free account, add an uptime monitor for https://<production host>/health, 'URL becomes unavailable', check frequency 3 minutes, enable confirmation from another region (recovery period default), on-call email to David only, recovery notifications on. Then stop the app briefly (or point the monitor at a bad path) to confirm an alert email and a recovery email arrive, and check off AC #1 and #3.

---
<!-- COMMENTS:END -->
