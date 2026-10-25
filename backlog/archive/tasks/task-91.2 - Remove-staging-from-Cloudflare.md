---
id: TASK-91.2
title: Remove staging from Cloudflare
status: done
assignee: []
created_date: '2026-10-22 09:54'
updated_date: '2026-10-23 11:23'
labels:
  - quick
dependencies: []
parent_task_id: TASK-91
type: chore
ordinal: 191000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** A DNS record pointing at a destroyed server's IP can be taken over by whoever gets that IP next.

Delete staging's DNS record and its Cloudflare Access application.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 No DNS record or Access application for staging remains
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Deleted the staging.edenflowers.fi and images-staging.edenflowers.fi DNS records and staging's Access application on 2026-10-23.
<!-- SECTION:NOTES:END -->
