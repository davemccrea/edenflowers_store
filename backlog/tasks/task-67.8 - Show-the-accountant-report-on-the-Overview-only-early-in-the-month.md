---
id: TASK-67.8
title: Show the accountant report on the Overview only early in the month
status: ready-for-agent
assignee: []
created_date: '2026-10-20 06:52'
updated_date: '2026-10-20 06:53'
labels:
  - quick
dependencies: []
parent_task_id: TASK-67
type: feature
ordinal: 149000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The report is downloaded once a month, just after it closes; the rest of the month it takes space from today's work.

### What to build

- Show the report widget on days 1 to 10 of the month, below everything else. Outside those days a quiet link to the download stays in the This month section, so it is never unreachable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The widget shows on days 1 to 10 and the link otherwise
- [ ] #2 The existing suite passes
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-20 06:53

---

A Reports page is planned (TASK-68). Once it exists, the accountant report may move there and this widget becomes a link.

---
<!-- COMMENTS:END -->
