---
id: TASK-91.3
title: Remove staging's Stripe sandbox
status: done
assignee: []
created_date: '2026-10-22 09:54'
updated_date: '2026-10-23 11:26'
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
- [x] #1 No webhook endpoint points at staging
- [x] #2 No API key used only by staging is still active
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Deleted staging's webhook endpoint on 2026-10-23.

Staging used the same sandbox secret key as local dev, so no key was staging-only. Not rolled: the only other copy goes when the server is destroyed (TASK-91.5).
<!-- SECTION:NOTES:END -->
