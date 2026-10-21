---
id: TASK-89.1
title: Add a /health route
status: ready-for-agent
assignee: []
created_date: '2026-10-21 19:51'
labels:
  - quick
dependencies: []
parent_task_id: TASK-89
type: feature
ordinal: 184000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The uptime monitor needs a URL that fails when the app or its database is down, which a cached page behind Cloudflare can't do.

Add `GET /health`. It runs `SELECT 1` through the Repo and returns 200 `ok`, or 503 when the query fails.

- Route it outside the `:browser` pipeline, next to `/sitemap.xml`, so sessions, locale and the maintenance plug don't touch it. It answers 200 during maintenance mode: that downtime is planned.
- Send `cache-control: no-store` so Cloudflare never serves a cached 200.
- Check the database only, not Oban, Stripe or email.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GET /health returns 200 when the app can query the database
- [ ] #2 GET /health returns 503 when the database query fails
- [ ] #3 /health responds with cache-control: no-store
- [ ] #4 /health answers 200 while maintenance mode is on
<!-- AC:END -->
