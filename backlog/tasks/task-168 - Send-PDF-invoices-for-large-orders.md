---
id: TASK-168
title: Create and manage standalone invoices in admin
status: in-progress
assignee: []
created_date: '2026-11-01 20:39'
updated_date: '2026-11-02 15:42'
labels:
  - spec
  - admin
  - customers
dependencies: []
priority: medium
type: feature
ordinal: 314000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie creates and manages standalone invoices in admin for weddings and bespoke work, without creating a store order or course booking.

**Why:** Jennie needs to replace Zervant for occasional bespoke invoices. Deriving invoices from purchase balances complicates VAT, payments and cancellation handling, while regular orders and courses already have their own payment workflows.

## Agreed scope
- Standalone invoices own their buyer details, billed lines, dates, language and totals. No required or optional order/course relationship in this implementation.
- A wedding is simply two ordinary invoices, one for the booking advance and one for the remaining charges. Jennie supplies the descriptions and amounts. No wedding entity, advance/final types, linked instalments or automatic balance reconciliation between documents.
- Every invoice bills only its own lines. Its VAT table describes its own amount, not an entire wedding or purchase.
- Editable drafts have no official number and do not count as receivables. Issuing assigns the sequential number and freezes the invoice, seller, buyer, lines and numeric VAT totals. An email failure does not undo issuance. Issuing and sending are distinct operations.
- Buyer entry supports consumers and businesses directly on the invoice, with name, email, address, company details where applicable and optional customer reference. Language is fi, sv or en. No customer directory is required.
- Lines have description, quantity, VAT-inclusive unit price and VAT rate. Invoice total is calculated from lines, not entered as an unrelated amount. Supply/advance date information belongs to the invoice rather than being inferred from a purchase.
- Retain the configured seller details, bank-transfer-only payment block, viitenumero, virtual barcode, Typst renderer, 14-day default due date, manual reminders and shared sequential invoice/credit-note numbering from 1337. Retain the current configured interest field; no interest collection engine is added.
- Invoice payments belong directly to the invoice. Existing order/course payments retain their ownership and behaviour.
- Extend the existing monthly accounting report to include standalone invoice payments using the invoice's frozen VAT breakdown, alongside existing shop sales, exactly once. Keep the existing cash-based reporting convention and month-end receivables. Update ADR 0004 to describe both sources.
- A credit note reverses one entire issued invoice with no money recorded against it, including its frozen base and VAT per rate. No partial credits or crediting paid/part-paid invoices. Jennie consults the accountant if such an exceptional correction arises; no undo-and-rebook workaround is required.
- No invoices have been issued, and the new system/site is not live. There is no issued-invoice migration obligation. Preserve unrelated existing orders, bookings and payments; no blanket database resets.

## Remove from the old implementation
Purchase-based invoice eligibility, amount defaults and outstanding-invoice calculations; invoice creation/payment selection in order/course screens; cancellation-fee invoicing; purchase-derived invoice PDF lines; purchase emails or receipts promising invoices or reflecting the abandoned invoice integration. Preserve ordinary payment recording, refunds, cancellation behaviour and legacy bank-transfer records.

## Out of scope
Wedding modelling; relationships between booking and remainder invoices; customer directory; catalog integration; payment links; e-invoicing; bank imports; automated reminders; arbitrary partial credits; paid-invoice corrections; automatic cancellation-charge tax classification.

## Plan history
This scope supersedes the original purchase-linked design and its implementation notes. TASK-168.1 through TASK-168.8 record that completed implementation, not acceptance of the replacement.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Jennie can draft, issue, email, download and manage an invoice entirely from standalone admin without an order or course booking
- [x] #2 Each issued invoice freezes its own billed lines, buyer/seller details, numeric totals and correct VAT breakdown; wedding booking and remainder invoices require no special modelling
- [x] #3 Drafts are editable and unnumbered; issued documents are immutable, sequentially numbered and remain issued when email delivery fails
- [x] #4 Standalone bank-transfer payments and reversals determine invoice balances without changing any order or booking balance
- [x] #5 An unpaid invoice can be fully reversed by a numbered credit note with the original reference and negative base/VAT breakdown; paid and partly paid corrections remain outside the automated workflow
- [x] #6 The monthly report includes standalone invoice payments and their VAT exactly once and reconstructs unpaid issued invoices at month end
- [x] #7 Regular order/course payment, cancellation, receipt and email flows work without the abandoned purchase-linked invoice integration
- [ ] #8 Finnish/Swedish invoice translations are reviewed and the release image renders invoice and credit-note PDFs offline
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Planning only: implementation is not started. The agreed decisions are recorded in this spec; tickets remain needs-triage under the repository issue-tracker convention.

1. TASK-168.9: replace purchase-derived invoices with standalone drafts, lines and immutable issuance. Reuse numbering, references, config and the existing resource where practical; no new wedding or customer domain.

2. TASK-168.10: render/send documents from their own financial snapshot and reverse unpaid invoices with exact negative VAT.

3. TASK-168.11: extend payment ownership to standalone invoices and record/reverse bank receipts with correct locking.

4. TASK-168.12: include invoice receipts in monthly sales, reconcile partial-payment VAT and retain historical receivables; update ADR 0004 and CONTEXT.md.

5. TASK-168.13: provide the standalone admin workflow using the finished domain actions.

6. TASK-168.14: remove old order/course invoice integration while retaining ordinary payment and cancellation behaviour.

7. TASK-168.15: run financial/admin regression checks, validate clean and upgrade migrations, review localized documents and verify offline rendering in the release image.

Validation concentrates on domain transitions, ownership constraints, exact VAT/rounding, concurrency, historical month-end reports, admin authorization and retained shop workflows. No tests are required merely for this planning update.

No issued invoice migration is needed. Preserve all unrelated existing data. Do not build paid-invoice correction, wedding instalment relationships, catalog/customer integrations or an automatic order balance connection.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Cancelling now asks for the cancellation charge Jennie keeps (0 to the Total due, paid or not) instead of a refund amount. Paid above it is refunded; any of it unpaid is left as a Balance to collect, which she invoices from the cancelled row. A booking's charge starts at the course's terms, an order's at 0.

The invoice PDF was simplified after comparing with Zervant's invoice 1336: no buyer email, order number, subtotal, BIC or payee field; the delivery date, viitenumero and late payment interest are facts beside the buyer; the VAT table always shows; the payment block has IBAN, viitenumero, due date, amount, virtual barcode digits and bar code. The seller (name, address, Y-tunnus, IBAN) lives in config :edenflowers, :seller, which receipts and invoices both print; shop.toml keeps only the pickup place and contact details.

Standalone implementation TASK-168.9–14 complete. TASK-168.15 automated verification passed, including 1766 tests and actual offline localized PDFs in the built release image. It is ready-for-human for native/Jennie review, seller/bank confirmation and live Zervant cutover numbering; parent AC8 remains open. Evidence and remaining checks: TASK-168.15 notes.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-01 23:14

---

All subtasks done on branch pdf-invoices. Left before go-live: set Zervant's last invoice number + 1 (>= 100) and the real IBAN and BIC in config :edenflowers, :invoices; review fi/sv drafts R05, R06, R07, T21, T22, T23 in priv/gettext/review-queue.md and the untranslated invoice admin strings; build the release image once to confirm offline Typst rendering. AC 8 (Zervant no longer needed) is checked once that's done.

---

author: @claude
created: 2026-11-02 13:55

---

Go-live config done: invoices continue Zervant's series from 1337 (its last was 1336), and the seller is Jennie McCrea, Stadsgatan 3, 65300 Vasa, with her real IBAN FI69 3939 0018 3959 05, in config :edenflowers, :seller (receipts print it too). BIC dropped: SEPA transfers need only the IBAN. Late payment interest is a fixed 8,00 %. Still left before go-live: review fi/sv drafts R05, R06, R07, R09, T21, T22, T23 in priv/gettext/review-queue.md and the untranslated invoice admin strings; build the release image once to confirm offline Typst rendering. AC 8 (Zervant no longer needed) is checked once that's done.

---

author: @codex
created: 2026-11-02 15:03

---

Scope revised with David: invoices are independent of orders/courses; weddings are two ordinary invoices without extra modelling. Standalone receipts enter monthly sales reporting. No invoices have been issued and the new system/site is not live. Paid/part-paid invoice corrections are referred to the accountant. TASK-168.1 through TASK-168.8 remain historical completed work and do not define the revised scope.

---

author: @codex
created: 2026-11-02 15:05

---

David confirmed the standalone scope and delegated implementation. Assignments: invoice-model owns .9 then .13; invoice-documents owns .10 then .14; invoice-payments owns .11 then .12; invoice-verification owns .15. Follow dependencies and coordinate shared files. Agreed product decisions are recorded in the spec; no new requirements interview is needed.

---
<!-- COMMENTS:END -->
