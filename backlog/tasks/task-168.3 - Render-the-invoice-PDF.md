---
id: TASK-168.3
title: Render the invoice PDF
status: ready-for-agent
assignee: []
created_date: '2026-11-01 20:57'
updated_date: '2026-11-01 21:02'
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

Typst template beside the receipt one. It shows seller and buyer details, the invoice number, date, due date and customer reference, the purchase's lines with VAT per rate (reuse `Vat.breakdown`), what's already been invoiced or paid, and "Due on this invoice". The payment block has IBAN, BIC, viitenumero, virtuaaliviivakoodi (version 4, built from IBAN, amount, reference and due date) and the late-interest line. Labels are in fi, sv and en. Add sample fixtures and render all three languages.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The PDF renders in fi, sv and en from the invoice's frozen data
- [ ] #2 The virtual barcode decodes to the right IBAN, amount, viitenumero and due date
- [ ] #3 A partial invoice shows the full lines, the earlier invoiced or paid amount and the amount due on it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Existing Typst templates (researched 2026-11-01):

- laskutys (https://typst.app/universe/package/laskutys, v1.1.0, MIT-0): Finnish VAT invoice template, fi/sv/en, optional bank barcode (FI IBANs only) and EPC QR. Not used as-is: it works out VAT itself from items (docs admit cent rounding errors), so it would disagree with Vat.breakdown; it makes an RF creditor reference (ISO 11649), not a domestic viitenumero; it has no credit note, already-invoiced/paid or reminder variants. Read its source for which fields to include and how to lay them out.
- invoice-pro: German DIN 5008 layout with GiroCode QR. Not relevant.
- rustycure: Typst QR and bank barcode package (invoice-pro uses it for QR).
- tiaoma: general Typst barcode generator (Zint), can print Code 128.

Approach: own template beside the receipt one. Elixir works out the viitenumero check digit (7-3-1 weights) and the 54-digit virtuaaliviivakoodi (version 4) string; Typst only prints it as Code 128 via tiaoma or rustycure. Spec: Finanssiala Bank bar code guide, https://www.finanssiala.fi/wp-content/uploads/2021/03/Bank_bar_code_guide.pdf. The bank-barcode Rust crate (https://docs.rs/bank-barcode) is a reference implementation for test vectors.
<!-- SECTION:NOTES:END -->
