---
id: TASK-168.3
title: Render the invoice PDF
status: done
assignee: []
created_date: '2026-11-01 20:57'
updated_date: '2026-11-02 13:55'
labels: []
dependencies:
  - TASK-168.2
parent_task_id: TASK-168
type: feature
ordinal: 317000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The PDF is what the customer actually reads and pays from, and what the accountant files.

Typst template beside the receipt one. It shows seller and buyer details, the invoice number, date, due date and customer reference, the purchase's lines with VAT per rate (reuse `Vat.breakdown`), what's already been invoiced or paid, and "Due on this invoice". The payment block has IBAN, viitenumero, virtuaaliviivakoodi (version 4, built from IBAN, amount, reference and due date) and the late-interest line. Labels are in fi, sv and en. Add sample fixtures and render all three languages.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The PDF renders in fi, sv and en from the invoice's frozen data
- [x] #2 The virtual barcode decodes to the right IBAN, amount, viitenumero and due date
- [x] #3 A partial invoice shows the full lines, the earlier invoiced or paid amount and the amount due on it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Payments.InvoicePdf (content/1, build_payload/1, payload/1, generate/1) renders priv/receipts/invoice.typ via Edenflowers.Typst.render/3, now shared with Orders.Receipt. Lines, totals and VAT come from Receipt.build_payload/1 in the invoice's locale; earlier invoices (lower numbers) and money paid outside any invoice before it was made (net) print above Due on this invoice. Everything but the labels, seller details and a booking's translated course name included, is frozen onto Invoice.content as the invoice is made (Changes.FreezeInvoiceContent, after the number is taken); renders, the email attachment and resends read it, and a Credit note takes its buyer and seller from it. Payments.VirtualBarcode.version_4/4 builds the 54 digits, tested against all Bank Bar Code Guide 5.3 version 4 examples; tiaoma 0.3.0 prints it as Code 128 set C, vendored in priv/receipts/packages and found via --package-path, so no network in dev, CI or the release image. Labels in the receipts domain (InvoiceLabels); fi/sv are AI drafts, queued as R05. Samples: sample/invoice.{fi,fi.final,sv,en.course}.json, preview with typst compile invoice-main.typ --package-path packages --input fixture=…
<!-- SECTION:NOTES:END -->
