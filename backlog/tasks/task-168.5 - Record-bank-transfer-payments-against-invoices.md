---
id: TASK-168.5
title: Record bank transfer payments against invoices
status: ready-for-agent
assignee: []
created_date: '2026-11-01 20:57'
labels: []
dependencies:
  - TASK-168.2
parent_task_id: TASK-168
type: feature
ordinal: 319000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie needs to see which invoices are settled without cross-checking her bank against Zervant.

Rename the Zervant payment method to a bank transfer invoice (existing payments keep it). When Jennie records one, she picks the invoice it pays. Add a calculation for an invoice's status (open, paid, cancelled) from its Payments. The existing Payment received email still goes out.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Zervant payment method is renamed and existing payments keep it
- [ ] #2 A bank transfer Payment can be linked to one of the purchase's invoices
- [ ] #3 An invoice is paid once its Payments cover its amount
<!-- AC:END -->
