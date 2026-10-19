---
id: TASK-63
title: >-
  Set each upcoming course's late-cancellation fee after the next production
  deploy
status: done
assignee: []
created_date: '2026-10-19 10:11'
updated_date: '2026-10-19 13:52'
labels:
  - admin
  - quick
  - spec
dependencies: []
priority: medium
type: chore
ordinal: 133000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every course that exists at the next production deploy gets a €15 late-cancellation fee from the TASK-37 migration, including courses booked under the old terms, which promised a full refund only up to 7 days before and said nothing about a fee.

**Why:** Customers who booked before the fee existed shouldn't find one kept when they cancel late, unless Jennie decides it should apply.

Decided: Jennie sets each upcoming course's fee by hand in the course form after the deploy (0 where the old terms should stand), rather than a migration backfill.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 After the production deploy, every upcoming course's late-cancellation fee is what Jennie wants it to be
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-19 10:11

---

Left for Jennie: after deploying to production, open each upcoming course in the admin and set its late-cancellation fee (0 to keep the old full-refund terms).

---

author: @claude
created: 2026-10-19 13:52

---

Done by the user on 2026-10-19: each upcoming course's late-cancellation fee is set.

---
<!-- COMMENTS:END -->
