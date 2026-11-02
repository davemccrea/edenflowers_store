---
id: TASK-168.9
title: 'Make invoices own their drafts, billed lines and issued content'
status: done
assignee:
  - '@invoice-model'
created_date: '2026-11-02 15:03'
updated_date: '2026-11-02 15:10'
labels: []
dependencies: []
references:
  - lib/edenflowers/payments/invoice.ex
  - lib/edenflowers/payments/changes/issue_invoice.ex
  - lib/edenflowers/payments/number_series.ex
parent_task_id: TASK-168
type: feature
ordinal: 323000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** An invoice must describe the work Jennie is billing without reconstructing an order or booking.

Replace purchase ownership and arbitrary amount defaults with standalone buyer details and billed lines. Drafts are editable and unnumbered; issuance assigns the number and freezes the document. Keep exact numeric quantity, VAT rate, monetary totals and VAT breakdown separate from translated display strings. Use VAT-inclusive unit prices, validate quantities and rates, and define deterministic cent rounding. Store the invoice's relevant supply/advance date information explicitly. Preserve the existing number-series lock and issuing transaction. No invoice has been issued, but migrations must preserve unrelated purchase/payment data.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An invoice can be drafted and issued without order_id or course_registration_id, and its total is calculated from its own lines
- [x] #2 Draft changes do not consume numbers or create receivables; concurrent issuance cannot duplicate numbers or issue the same draft twice
- [x] #3 Issuance freezes all financial and buyer/seller data; later edits or config changes cannot change issued content
- [x] #4 Mixed VAT rates, fractional quantities and cent rounding yield consistent line, base, VAT and gross totals; invalid or empty invoices cannot be issued
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Replace purchase-owned create with editable standalone drafts and locked issuance; store typed exact line financial snapshots and freeze rendered content. Preserve shared numbering and unrelated purchase data. Generate schema migration and test draft/issue, rounding, immutability, authorization and duplicate issue behavior.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented standalone :create/:update_draft and locked :issue actions. Drafts have nil number/reference/content and :draft status; issue validates buyer/dates/lines, assigns shared number and freezes seller, buyer, numeric financial_snapshot and rendered content. Canonical exact decimal strings keep quantities/prices/rates and numeric totals separate from display; extended gross and VAT-exclusive line base round half-up to cents, VAT is their difference, per-rate sums conserve totals. Migration 20261102150840 adds standalone snapshots and draft nullability, drops former required purchase ownership constraint without deleting data. Tests: standalone_invoice_test + invoice_financials_test + invoice_pdf_test: 11 tests passed; invoice_issuance_concurrency_test: 1 passed using independent committed transactions and targeted cleanup. Covers stale edits/double issue, independent concurrent number uniqueness, auth, invalid/empty lines, fractional quantities, mixed VAT, zero rates, rounding, frozen seller/config and draft receivables. Legacy purchase relationships remain temporarily for TASK-168.14 removal. No staging or commit.
<!-- SECTION:NOTES:END -->
