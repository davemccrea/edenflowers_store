---
id: TASK-89.2
title: Create the uptime monitor in Better Stack
status: ready-for-human
assignee: []
created_date: '2026-10-21 19:51'
updated_date: '2026-10-21 19:51'
labels: []
dependencies:
  - TASK-89.1
parent_task_id: TASK-89
type: chore
ordinal: 185000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** This is the part that actually emails David when the shop is down; the route alone tells nobody.

Once TASK-89.1 is deployed to production, create a Better Stack monitor on the free tier:
- URL: production `/health`, expecting 200, every 3 minutes.
- Keep the default confirmation from a second region before alerting.
- Alert David by email only, with recovery emails on.
- Keep the Better Stack login in the password manager.
- Add a line to `infra/README.md` naming the monitor and the URL it watches.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A failed /health check emails David
- [ ] #2 `infra/README.md` names the monitor and its URL
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-21 19:51

---

Left for David: needs his Better Stack account and a production deploy of TASK-89.1.

---
<!-- COMMENTS:END -->
