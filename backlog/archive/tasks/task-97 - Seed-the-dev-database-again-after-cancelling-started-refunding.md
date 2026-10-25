---
id: TASK-97
title: Seed the dev database again after cancelling started refunding
status: done
assignee: []
created_date: '2026-10-22 19:46'
updated_date: '2026-10-22 19:48'
labels:
  - spec
  - developers
  - quick
dependencies: []
priority: medium
type: bug
ordinal: 203000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Seeding a fresh database fails: priv/repo/seeds.exs cancels Stripe-paid orders, and since TASK-92.2 cancelling refunds through Stripe by default, which refuses the seeds' fake payments ("Stripe refused the refund, so nothing was cancelled").

**Why:** every new worktree seeds its database, so every new worktree starts with no data until this is fixed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A fresh worktree seeds without error
- [x] #2 The seeded cancelled orders still show the states their comments describe
<!-- AC:END -->
