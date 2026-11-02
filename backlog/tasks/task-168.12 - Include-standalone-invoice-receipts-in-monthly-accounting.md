---
id: TASK-168.12
title: Include standalone invoice receipts in monthly accounting
status: done
assignee:
  - '@invoice-payments'
created_date: '2026-11-02 15:03'
updated_date: '2026-11-02 15:16'
labels: []
dependencies:
  - TASK-168.9
  - TASK-168.11
references:
  - lib/edenflowers/accounting/monthly_report.ex
  - docs/adr/0004-orders-are-the-sales-record.md
  - CONTEXT.md
parent_task_id: TASK-168
type: feature
ordinal: 326000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Standalone invoice receipts would otherwise be omitted because today's sales report assumes every payment belongs to an order or course.

Extend the existing report with invoice-owned payment rows sourced from the issued invoice's frozen numeric VAT amounts. Keep the current cash-based timing and existing order/course rows. Allocate partial receipts per rate with a documented deterministic cent policy; settlement/reversal must reconcile to the frozen invoice rather than accumulate rounding drift. Include unpaid issued invoices at historical month end, excluding drafts and credits effective by then. Unpaid credits must not invent a cash receipt or refund. Update ADR 0004 and domain documentation to make the additional sales source explicit without double counting issued documents and their receipts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Standalone receipts and reversals enter the sales sheet once on their Helsinki paid dates using frozen invoice VAT; existing purchase rows remain correct
- [x] #2 Mixed-rate partial receipts and final settlement reconcile to the invoice's gross/base/VAT without lost cents, division by zero or counting the issue itself as another cash sale
- [x] #3 Receivables reconstruct balances at month end even if payment or credit occurred later; drafts are excluded
- [x] #4 ADR 0004 and CONTEXT.md describe standalone invoice sales and payment ownership consistently with the report
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Allocate invoice receipts as differences between deterministic cumulative allocations of the frozen numeric VAT breakdown, preserving cents across partial receipts, settlement and reversals. Add invoice-owned cash rows alongside existing purchase rows, adapt historical receivables, verify Helsinki month boundaries and mixed rates, and update ADR0004 and domain glossary.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Standalone invoice-owned Payments now appear once in the existing cash sales sheet using frozen numeric VAT. Cumulative allocation differences reconcile partial receipts, final settlement and reversals across months, with deterministic cent ties and zero-gross handling. Historical receivables include issued documents only, freeze buyer/customer reference, and reconstruct later payments/credits correctly. Updated ADR0004, ADR0002 ownership wording and CONTEXT glossary. Validation: 16 accounting/allocation tests passed, including mixed-rate tiny receipts, full reversal/re-entry, Helsinki month boundaries, existing purchase rows, future credits/payments and drafts. Codegen check and gettext check passed; extracted catalogs and added sv/fi invoice source label.
<!-- SECTION:NOTES:END -->
