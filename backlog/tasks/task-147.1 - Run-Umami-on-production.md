---
id: TASK-147.1
title: Run Umami on production
status: done
assignee: []
created_date: '2026-10-30 17:41'
updated_date: '2026-10-31 10:16'
labels: []
dependencies: []
parent_task_id: TASK-147
type: chore
ordinal: 282000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The tracker needs somewhere to send visits. Umami compose service, its database and role on the host Postgres, vault secrets, renamed script and endpoint, and the umami database in the nightly backup.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Compose template runs a pinned Umami image on host networking
- [x] #2 Postgres role and umami database are provisioned
- [x] #3 backup.sh dumps and mirrors the umami database
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-30 17:56

---

Code done. Left for David: vault secrets, just provision, tunnel hostname stats.edenflowers.fi -> localhost:3000, change Umami's default admin password, add the website, set umami_website_id, provision again. Steps in infra/README.md.

---
<!-- COMMENTS:END -->
