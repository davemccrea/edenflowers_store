---
id: TASK-168.10
title: Render and send standalone invoices and full credit notes
status: done
assignee:
  - '@invoice-documents'
created_date: '2026-11-02 15:03'
updated_date: '2026-11-02 15:11'
labels: []
dependencies:
  - TASK-168.9
references:
  - lib/edenflowers/payments/invoice_pdf.ex
  - priv/receipts/invoice.typ
  - priv/receipts/credit-note.typ
  - lib/edenflowers/payments/changes/send_invoice.ex
parent_task_id: TASK-168
type: feature
ordinal: 324000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Customers and their accountants need documents whose tax amounts match exactly what each invoice bills.

Render from the standalone issued snapshot, never a purchase receipt payload. Keep the existing localized PDF layout, seller, payment block, reference/barcode and manually sent emails/reminders. Remove whole-purchase totals, earlier-purchase deductions and not-charged/invoice-later rows. Credit notes copy and negate the original invoice's frozen financial breakdown and refer to its number. Keep only full crediting with zero recorded money; serialize credit creation against payment recording. Generate email content and recipients from invoice data.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Booking and remainder invoices print only their respective billed lines and VAT; rendering loads no order or course
- [x] #2 A full credit note reverses the original gross, base and VAT per rate exactly and names the original invoice
- [x] #3 Only issued invoices can be sent or credited, and drafts cannot be downloaded as official numbered documents
- [x] #4 Email failures leave issued documents intact and retryable; fi/sv/en downloads, resends and reminders use the frozen document
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Implement against coordinated, stable TASK-168.9 snapshot contract while its resource work lands. Render frozen standalone lines/VAT and seller details, retain localized layout/payment block and immutable resends; use standalone invoice email/previews; fully negate frozen credit-note financials and reject drafts/paid corrections under existing invoice row lock. Verify focused financial/PDF/email tests; coordinate invoice.ex with model owner.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Standalone renderer now freezes own lines/VAT and seller only; no purchase loads or prior-advance deductions. Credit notes negate frozen line/VAT/gross values exactly and use original buyer/date/reference; existing credit transaction locks invoice against receipts, draft guard added and paid corrections direct to accountant. Standalone emails/previews retain frozen payee, attachments and manual reminders. fi/sv translations for new standalone copy added as native-review drafts. Validation: mix compile; 9 focused document tests pass including real offline Typst invoice/credit rendering in fi/sv/en, draft restrictions, full credit exactness, failed-send issuance persistence and retry reminder. No schema generation performed by document agent.
<!-- SECTION:NOTES:END -->
