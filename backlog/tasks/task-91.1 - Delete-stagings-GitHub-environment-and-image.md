---
id: TASK-91.1
title: Delete staging's GitHub environment and image
status: done
assignee: []
created_date: '2026-10-22 09:54'
updated_date: '2026-10-23 11:26'
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
- [x] #1 The repo has no staging environment
- [x] #2 GHCR has no staging tag
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Deleted the staging GitHub environment on 2026-10-23. The GHCR staging tag is left: the gh token lacks read:packages/delete:packages.

Deleted the GHCR version tagged only staging (sha256:957952c2..., 2026-10-21) on 2026-10-23.
<!-- SECTION:NOTES:END -->
