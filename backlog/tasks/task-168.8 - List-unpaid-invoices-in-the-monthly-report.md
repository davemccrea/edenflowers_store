---
id: TASK-168.8
title: List unpaid invoices in the monthly report
status: done
assignee: []
created_date: '2026-11-01 20:57'
updated_date: '2026-11-01 23:14'
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

Add a section listing invoices dated by the end of the reported month and still unpaid then: number, date, due date, buyer and amount open. Sales are still booked from orders, per ADR 0004.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The monthly report lists invoices unpaid at month end with number, dates, buyer and amount open
- [x] #2 Sales totals in the report are unchanged
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Invoice gains read action open_at (date arg: made by then, no Credit note dated by then, amount_open_at > 0) and calcs amount_open_at (date arg: amount less Payments with paid_at on or before that Helsinki day, refunds and Undos netted), buyer (company name for a business customer, else buyer name) and purchase_reference. Payments.list_open_invoices. Monthly report gains a fourth sheet, Kundfordringar: number, invoice date, due date, buyer, reference, invoice amount, unpaid at month end, and a Summa row. Paid or cancelled later still lists, so the sheet reads the same whenever it is built. Sales sheet untouched (ADR 0004). Listed by invoice date, not sent_at: a receivable dates from the invoice date, whether or when it was emailed. sv/fi headings AI-drafted, queued as R07.
<!-- SECTION:NOTES:END -->
