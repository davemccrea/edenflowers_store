---
id: TASK-160.5
title: Show vouchers sold and spent in the monthly report
status: done
assignee: []
created_date: '2026-11-01 17:32'
updated_date: '2026-11-05 20:09'
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
- [x] #1 Voucher purchases are not counted as sales
- [x] #2 Spent voucher amounts are counted as sales at the bought items' VAT rates
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-05: Payments for a Gift voucher sale (whose VAT breakdown is empty, so they used to drop out of the report entirely) now go on a 'Sålda presentkort' sheet after sales, with their sum. :voucher payments were already split at the bought order's rates, or a course's rate, like any payment; the test pins both.
<!-- SECTION:NOTES:END -->
