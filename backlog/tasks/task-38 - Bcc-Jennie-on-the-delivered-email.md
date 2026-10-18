---
id: TASK-38
title: Bcc Jennie on the delivered email
status: done
assignee: []
created_date: '2026-10-18 18:22'
updated_date: '2026-10-18 18:36'
labels:
  - spec
  - admin
  - quick
dependencies: []
priority: low
type: chore
ordinal: 99000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie gets a copy of every booking-related email and files them with a Fastmail rule. The delivered email is the only one she doesn't see.

Add `bcc(from_address())` to `Email.order_delivered/1`, as the other order emails have.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The delivered email bccs the shop address
<!-- AC:END -->
