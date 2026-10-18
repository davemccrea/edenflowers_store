---
id: TASK-18.9
title: Rename DashboardLive to OverviewLive
status: done
assignee: []
created_date: '2026-10-18 06:37'
updated_date: '2026-10-18 06:39'
labels:
  - quick
dependencies: []
parent_task_id: TASK-18
type: refactor
ordinal: 78000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

The admin landing page was renamed to Overview, but only its visible text changed. The module `EdenflowersWeb.Admin.DashboardLive`, its file `dashboard_live.ex` and `dashboard_live_test.exs` still say Dashboard, as does a comment in `Order` ("the dashboard's read").

### What to build

- Rename the module, file and test to `OverviewLive` / `overview_live`, and update the router.
- Update comments that mean the admin Overview. Leave the Stripe dashboard, the LiveDashboard route and the Oban and ErrorTracker dashboards alone.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No reference to the admin Overview calls it the dashboard
- [x] #2 The existing suite passes
<!-- AC:END -->
