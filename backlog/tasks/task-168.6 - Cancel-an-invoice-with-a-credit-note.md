---
id: TASK-168.6
title: Cancel an invoice with a credit note
status: done
assignee: []
created_date: '2026-11-01 20:57'
updated_date: '2026-11-01 22:49'
labels: []
dependencies:
  - TASK-168.4
  - TASK-168.5
parent_task_id: TASK-168
type: feature
ordinal: 320000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** A sent invoice is in the customer's and the accountant's hands, so a mistake has to be undone with a document, not by editing it.

Cancelling a sent invoice issues a credit note (hyvityslasku) from the same number series. It names the original invoice and credits its amount. The credit note is rendered as a PDF and emailed like an invoice. A cancelled invoice no longer counts toward the amount invoiced, so the next invoice defaults to the right amount. A paid invoice can't be cancelled.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Cancelling an invoice issues a numbered credit note naming it
- [x] #2 The credit note PDF and email go out in the invoice's language
- [x] #3 Cancelled invoices don't count toward the amount already invoiced
- [x] #4 A paid invoice can't be cancelled
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Payments.CreditNote in its own table (number, credit_date, reason, sent_at, unique invoice_id), not a kind on Invoice: an Invoice's due date, viitenumero, amount > 0, payments and status don't apply, and every invoice query would need a kind filter. Payments.NumberSeries takes the next number for both under one advisory lock (GREATEST of both tables' max). Buyer, language and amount are read from the immutable Invoice. Invoice.status is :cancelled once a credit note exists (checked before :paid), so it leaves open_invoices, open_invoices_amount and the payment drawer; InvoiceOfPurchase refuses a Payment against it. Cancel = CreditNote :create (Payments.cancel_invoice), refused unless Invoice.cancellable? (open, amount_paid == 0): paid and part-paid both refused, undo Payments first. Changes.SendWhenCreated (renamed from SendNewInvoice) and SendCreditNote email it with hyvityslasku-/kreditnota-/credit-note-N.pdf. PDF credit-note.typ shares page, masthead and buyer block with invoice.typ via parts.typ; no lines, no payment block. earlier_invoices skips invoices cancelled before the one rendered. Admin: Cancel in invoice_list, cancel and send-credit-note modes in InvoiceDrawer (email ticked only if the invoice was sent), GET /admin/credit-notes/:id, invoice created/cancelled entries in the order log. fi/sv drafts queued as R06, T22.
<!-- SECTION:NOTES:END -->
