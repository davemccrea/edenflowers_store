---
id: TASK-168.15
title: Verify the standalone invoicing workflow before release
status: ready-for-human
assignee:
  - '@invoice-payments'
created_date: '2026-11-02 15:03'
updated_date: '2026-11-03 18:26'
labels: []
dependencies:
  - TASK-168.10
  - TASK-168.12
  - TASK-168.13
  - TASK-168.14
references:
  - priv/gettext/review-queue.md
  - priv/receipts/README.md
  - test/edenflowers/payments/invoice_pdf_test.exs
  - test/edenflowers/payments/standalone_invoicing_workflow_test.exs
parent_task_id: TASK-168
type: feature
ordinal: 329000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** This replaces Zervant for occasional real invoices and must work in the deployed release as well as development.

Exercise two ordinary wedding invoices independently, payment recording/reversal, reminders, unpaid credit/replacement and month-end reporting. Verify migration from a representative existing shop database and creation from a clean database. Review fi/sv document/email/admin text; replace stale course-linked sample fixtures and translation-review entries. Render PDFs offline inside the release image. Preserve real seller/bank config and number 1337 as the agreed starting point; verify Zervant has not advanced before cutover. Record manual findings and remaining human release checks.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 End-to-end checks cover independent wedding invoices, own-amount VAT, payment/reversal, unpaid credit/replacement and historical month-end accounting
- [x] #2 Clean and upgrade database checks pass while retaining existing order/course payments; targeted domain, accounting and admin tests pass
- [x] #3 The release image renders localized invoice and credit-note PDFs offline with valid reference numbers/barcodes
- [ ] #4 Finnish/Swedish text and sample PDFs are reviewed, current seller/bank details and starting number are verified, and remaining release checks are explicit
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Run end-to-end standalone/wedding, financial and retained purchase/admin regressions; run clean and representative upgrade migrations in throwaway local databases preserving original worktree data; build the release image and render localized invoice/credit PDFs with networking disabled; record text/sample review and explicit remaining human cutover checks. Coordinate concrete failures with owners and do not stage or commit.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Automated verification complete: mix precommit passed all checks and JavaScript tests; 1766 Elixir tests, zero failures, one existing hidden-wedding-price skip. Clean migrations and upgrade from restored local production-v1.25.5 backup passed; all 18 orders, one booking and one payment retained with unchanged canonical row fingerprints. Original databases/backups untouched and throwaway databases removed. Actual linux/amd64 Docker release built and rendered seven fi/sv/en invoice/credit fixtures with --network none; all PDF outputs, reference check digits and full virtual barcode compositions validated. Apple Silicon emulation-only ERL_FLAGS workaround stayed in temporary context, repository Dockerfile unchanged. Localized samples and email previews AI-reviewed, obsolete review-queue items updated. AC4 remains unchecked: native sv/fi and Jennie financial-meaning approval, current seller/bank confirmation and live Zervant-last-number check require humans. Remaining checks: below; review PDFs/PNGs: tmp/invoice-verification/ and release/. No deployment/staging/commit.

Live dev smoke on 2 November: started pdf-invoices worktree with just port=4010 dev, leaving main-worktree port 4000 untouched. Authenticated real Chrome/Playwright checks passed draft persistence, decimal-comma line inputs, issuance, Finnish/Swedish invoice and full-credit downloads, partial/full bank receipts, reversals, paid-correction guard, independent ordinary wedding invoices, mobile overflow, store/course pages, admin order/course lists and existing details. No uncaught browser exceptions or external invoice emails. Local smoke payments were reversed and both smoke invoices credited. Found and fixed decimal-comma bank-transfer input: invoice lines normalized commas but payment form passed them directly to Ash decimal casting. Added a LiveView regression that failed before the fix; 16 focused invoice UI/payment tests pass, strict Credo and formatting/whitespace checks pass. Native review and cutover confirmations remain open.

Human checks before cutover (moved from the one-off docs/standalone-invoices-release-check.md, 3 Nov):
- Jennie approves Swedish financial/business meaning; native sv and fi reviewers approve PDF, email and admin wording: review queue R05–R07, R09–R12 and T21–T25. Accountant review stays appropriate for VAT, credit and receivables terms.
- Confirm the seller details and bank account: Jennie McCrea, Y-tunnus 2944459-6, Stadsgatan 3, 65300 Vasa, IBAN FI69 3939 0018 3959 05.
- Immediately before the first live invoice, confirm Zervant has not gone past 1336, so the shop's first number 1337 continues the series.
- Re-run the upgrade check against a production backup: the branch's migrations were regenerated as one (20261103182419_add_invoices) after the 2 Nov upgrade check.
<!-- SECTION:NOTES:END -->
