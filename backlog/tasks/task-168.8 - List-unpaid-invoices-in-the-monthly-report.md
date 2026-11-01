---
id: TASK-168.8
title: List unpaid invoices in the monthly report
status: ready-for-agent
assignee: []
created_date: '2026-11-01 20:57'
labels: []
dependencies:
  - TASK-168.5
parent_task_id: TASK-168
type: feature
ordinal: 322000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The accountant got receivables from Zervant. Once Zervant is gone, the monthly report has to show what's still owed.

Add a section listing invoices sent and still unpaid at the end of the reported month: number, date, due date, buyer and amount open. Sales are still booked from orders, per ADR 0004.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The monthly report lists invoices unpaid at month end with number, dates, buyer and amount open
- [ ] #2 Sales totals in the report are unchanged
<!-- AC:END -->
