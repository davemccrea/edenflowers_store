---
id: TASK-91.3
title: Remove staging's Stripe sandbox
status: ready-for-human
assignee: []
created_date: '2026-10-22 09:54'
labels:
  - quick
dependencies: []
parent_task_id: TASK-91
type: chore
ordinal: 192000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Stripe keeps retrying webhooks to an endpoint that no longer answers, and unused API keys are secrets left lying around.

Delete staging's webhook endpoint. Before deleting the sandbox itself, check whether local dev (`.env` and the worktrees' `.env`) uses the same sandbox: if it does, keep the sandbox and roll its keys instead.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No webhook endpoint points at staging
- [ ] #2 No API key used only by staging is still active
<!-- AC:END -->
