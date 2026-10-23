---
id: TASK-110
title: Developer flag that hides System tools from the shop admin
status: needs-triage
assignee: []
created_date: '2026-10-23 20:28'
labels:
  - spec
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 213000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Give developer accounts their own flag, so the shop admin no longer sees or reaches the System tools (Email previews, Errors, Oban, AshAdmin).

**Why:** Jennie's admin sidebar is crowded with tools only the developer uses, and AshAdmin can edit any record past the normal order rules, so stumbling into it risks bad data.

Today `admin` is the only flag on User, so every admin gets the System section.

Proposed: a `developer` boolean beside `admin` (not a role hierarchy), set only on mail@dmccrea.me. Non-developers don't see the System nav and can't reach /admin/errors, /admin/oban or /admin/ash.

Open: whether Email previews should stay visible to the shop admin, and how the flag gets set in prod (seed, data fix, or AshAdmin).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A non-developer admin sees no System section in the admin sidebar
- [ ] #2 A non-developer admin is refused at /admin/errors, /admin/oban and /admin/ash
- [ ] #3 mail@dmccrea.me keeps every System link and route
<!-- AC:END -->
