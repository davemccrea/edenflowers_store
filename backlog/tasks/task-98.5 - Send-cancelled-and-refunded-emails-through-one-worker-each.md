---
id: TASK-98.5
title: Send cancelled and refunded emails through one worker each
status: ready-for-agent
assignee: []
created_date: '2026-10-22 19:47'
labels: []
dependencies: []
parent_task_id: TASK-98
type: refactor
ordinal: 209000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** the email workers branch on order vs booking to load, translate and pick a template, twice.

One worker per email calling `Email.cancelled/3` and `Email.refunded/…`, which pick the template per resource; each resource loads what its email needs. The cancelled email's BCC follows who cancelled: a record copy when Jennie cancels, her inbox when the customer does.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Neither worker branches on the resource
- [ ] #2 The cancelled email's BCC follows cancelled_by for orders and bookings
<!-- AC:END -->
