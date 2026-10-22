---
id: TASK-91.1
title: Delete staging's GitHub environment and image
status: ready-for-human
assignee: []
created_date: '2026-10-22 09:54'
labels:
  - quick
dependencies: []
parent_task_id: TASK-91
type: chore
ordinal: 190000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The `staging` environment holds SSH deploy secrets for a server that is going away.

In the repo's GitHub settings, delete the `staging` environment with its secrets (DEPLOY_HOST, DEPLOY_USER, DEPLOY_SSH_KEY). In the GHCR package, delete the `staging` image tag.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The repo has no staging environment
- [ ] #2 GHCR has no staging tag
<!-- AC:END -->
