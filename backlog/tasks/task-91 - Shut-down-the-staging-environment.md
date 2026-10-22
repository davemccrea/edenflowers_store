---
id: TASK-91
title: Shut down the staging environment
status: ready-for-human
assignee: []
created_date: '2026-10-22 09:54'
labels:
  - spec
  - admin
dependencies: []
priority: low
type: chore
ordinal: 189000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Turn off everything staging still runs on outside this repo, now the repo deploys only to production.

**Why:** The repo no longer deploys to staging, so the server, its database and its service accounts cost money and keep secrets alive for nothing.

The repo side was removed in d17631f4: deploys, backups, rollbacks, image syncs and server commands target production only. What's left lives in GitHub, Cloudflare, Stripe, Brevo, phoenix-ansible and this machine, so only a human can do it. Destroy the server last, after anything that points at it is gone.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Nothing outside the repo refers to staging
- [ ] #2 The staging server is destroyed
<!-- AC:END -->
