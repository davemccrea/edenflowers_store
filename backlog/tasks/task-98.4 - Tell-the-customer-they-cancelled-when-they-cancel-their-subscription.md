---
id: TASK-98.4
title: Tell the customer they cancelled when they cancel their subscription
status: ready-for-agent
assignee: []
created_date: '2026-10-22 19:47'
labels: []
dependencies: []
parent_task_id: TASK-98
type: refactor
ordinal: 208000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** a customer who cancels their subscription is emailed the shop's wording for each open occurrence.

`Order :cancel` takes `cancelled_by`; `Subscription :cancel` passes who cancelled.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A customer's subscription cancel emails each occurrence with the customer wording
- [ ] #2 Jennie's subscription cancel keeps the shop wording
<!-- AC:END -->
