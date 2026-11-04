---
id: TASK-173.4
title: Record customer bank transfers on their invoices
status: done
assignee: []
created_date: '2026-11-04 17:44'
updated_date: '2026-11-04 18:32'
labels: []
dependencies:
  - TASK-173.3
parent_task_id: TASK-173
type: feature
ordinal: 335000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** a customer paying an invoice by bank transfer should show as paid in admin without Jennie entering it.

- The same sync also reads booked credit transactions. One whose reference number (ignoring spaces) equals an issued, open invoice's `reference_number` is recorded through `Invoice.record_payment` with the transaction's amount and booking date. A part payment is recorded; an overpayment is left for Jennie, because `record_payment` refuses more than is owed.
- Payment gains the bank transaction ID (nullable, unique identity) so a transaction seen on two runs is recorded once. Generate the migration with `mix ash.codegen`.
- No email to the customer, no notification to Jennie, nothing in admin marking it as from the bank.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A booked transfer with an open invoice's reference number is recorded as its payment with its amount and booking date
- [x] #2 The same bank transaction seen again is not recorded twice
- [x] #3 Transfers matching no open invoice are ignored
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Invoice :settle_from_bank (Payments.Actions.SettleInvoiceFromBank) records an incoming EUR transfer on the one open invoice with its reference, via record_payment with paid_at at midday Helsinki on the booking date. Payment.bank_transaction_id (unique identity) skips a transfer seen before. Overpayments are skipped.
<!-- SECTION:NOTES:END -->
