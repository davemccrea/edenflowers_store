---
id: TASK-168.14
title: Remove purchase-linked invoicing from orders and courses
status: done
assignee:
  - '@invoice-documents'
created_date: '2026-11-02 15:03'
updated_date: '2026-11-02 15:31'
labels: []
dependencies:
  - TASK-168.10
  - TASK-168.11
  - TASK-168.12
  - TASK-168.13
references:
  - lib/edenflowers/payments/invoiceable.ex
  - lib/edenflowers_web/features/admin/order_detail_live.ex
  - lib/edenflowers_web/features/admin/course_detail_live.ex
  - lib/edenflowers/orders/receipt.ex
parent_task_id: TASK-168
type: feature
ordinal: 328000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Leaving the former integration behind would keep unnecessary purchase-balance logic and promise invoices that the standalone workflow no longer creates.

Remove invoice eligibility fragments, purchase-owned invoice associations, balance defaults/aggregates, invoice creation/payment selectors and invoice-specific order logs. Remove purchase email/receipt claims tied to the abandoned integration and any business-detail UI or schema used solely by it. Retain details with an independent existing purpose. Preserve ordinary bank-transfer recording and all unrelated purchase, refund, cancellation and receipt behaviour; do not revert unrelated branch changes or indiscriminately roll back the branch. No bespoke cancellation-charge invoicing is added. Replace obsolete tests with regression coverage of the retained workflows.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Orders and bookings have no invoice management, invoice-balance deductions or dependency on standalone invoices
- [x] #2 Order/course confirmation, payment, reminder, cancellation and receipt flows no longer promise or require purchase-linked invoices
- [x] #3 Existing bank-transfer records, payment methods, balances and cancellation/refund workflows remain usable
- [x] #4 Schema/resource snapshots and migrations match the new ownership rules and can be applied without resetting existing purchase data
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Remove purchase Invoiceable/BusinessCustomer fragments, invoice actions/selectors/logs and purchase receipt/email promises; retain ordinary balances, cancellation/refund flows and historical payment methods. Replace obsolete integration tests with retained-flow regression checks. Coordinate final schema generation/migration with invoice-model owner, then notify invoice-payments for final verification.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Removed purchase-owned invoice and business-detail fragments/actions/fields, order/course invoice management and log entries, payment invoice selectors, receipt invoice references and cancellation invoice planning/promises. Standalone invoice order/course associations removed. Historical :invoice terms retained as bank transfer in UI; :zervant payments and purchase balance/refund/cancellation/reversal workflows preserved. Updated standalone preview cases, receipt fixtures/README and obsolete tests; added direct purchase bank-transfer/reversal and cancellation-charge regression tests. Model owner generated/reviewed final removal migration and snapshots, retaining purchase/payment rows with no reset. Validation: compile; 234 retained domain/email/PDF/admin tests passed; 8 focused PDF/purchase regression tests passed including supplied sub-cent unit-price precision; gettext.extract --merge and gettext.check passed; git diff --check clean. New fi/sv copy remains native-review draft for TASK-168.15.
<!-- SECTION:NOTES:END -->
