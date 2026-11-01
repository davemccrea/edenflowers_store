---
id: TASK-168.5
title: Record bank transfer payments against invoices
status: done
assignee: []
created_date: '2026-11-01 20:57'
updated_date: '2026-11-01 21:45'
labels: []
dependencies:
  - TASK-168.2
parent_task_id: TASK-168
type: feature
ordinal: 319000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie needs to see which invoices are settled without cross-checking her bank against Zervant.

Rename the Zervant payment method to a bank transfer invoice (existing payments keep it). When Jennie records one, she picks the invoice it pays. Add a calculation for an invoice's status (open, paid, cancelled) from its Payments. The existing Payment received email still goes out.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The Zervant payment method is renamed and existing payments keep it
- [x] #2 A bank transfer Payment can be linked to one of the purchase's invoices
- [x] #3 An invoice is paid once its Payments cover its amount
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Payment.invoice_id (belongs_to Invoice, Validations.InvoiceOfPurchase: same purchase). record_payment takes invoice_id; Undo copies it. Invoice: has_many payments, amount_paid aggregate (refunds/Undos net off), status calc (:open/:paid, :cancelled reserved for TASK-168.6), paid?, amount_unpaid. Invoiceable: has_many open_invoices (status == :open); open_invoices_amount sums their amount_unpaid. Kept the stored :zervant value (renaming needs a hand-written data migration); relabelled Bank transfer (invoice). Record payment drawer offers open invoices for a bank transfer, preselecting the only one.
<!-- SECTION:NOTES:END -->
