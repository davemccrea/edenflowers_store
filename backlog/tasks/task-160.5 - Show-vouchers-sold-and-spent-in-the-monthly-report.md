---
id: TASK-160.5
title: Show vouchers sold and spent in the monthly report
status: ready-for-agent
assignee: []
created_date: '2026-11-01 17:32'
labels: []
dependencies:
  - TASK-160.1
parent_task_id: TASK-160
type: feature
ordinal: 311000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** As multi-purpose vouchers, money paid for a voucher isn't a sale until it's spent. The report counts payments as sales, so without this, voucher sales would be taxed twice.

- Payments for voucher lines are shown as vouchers sold, outside sales.
- `:voucher` payments count as sales when spent, at the VAT rates of what they bought.
- Not now: outstanding vouchers (add when the accountant asks).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Voucher purchases are not counted as sales
- [ ] #2 Spent voucher amounts are counted as sales at the bought items' VAT rates
<!-- AC:END -->
