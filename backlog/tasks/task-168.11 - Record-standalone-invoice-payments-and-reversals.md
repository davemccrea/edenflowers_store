---
id: TASK-168.11
title: Record standalone invoice payments and reversals
status: done
assignee:
  - '@invoice-payments'
created_date: '2026-11-02 15:03'
updated_date: '2026-11-02 15:12'
labels: []
dependencies:
  - TASK-168.9
references:
  - lib/edenflowers/payments/payment.ex
  - lib/edenflowers/payments/validations/invoice_of_purchase.ex
  - lib/edenflowers/payments/changes/undo_payment.ex
parent_task_id: TASK-168
type: feature
ordinal: 325000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie must settle an invoice directly without inventing a shop purchase or changing its balance.

Extend the existing payment ledger so each payment belongs to exactly one order, course booking or standalone invoice. Remove the old requirement that an invoice payment also belongs to the invoice's purchase. Provide admin-authorized invoice payment recording and reversal with paid_at and bank-transfer method. Retain existing order/course recording and refund behaviour. Lock invoice state during payment/credit operations. Do not require undoing genuine receipts to credit a paid invoice; paid/part-paid correction is an accountant exception. No new automatic payment-received email is required for standalone invoices.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An invoice payment has invoice ownership only; database constraints reject missing or multiple owners and leave existing purchase-owned payments valid
- [x] #2 Partial payments and reversals give correct paid/unpaid balances and dates without affecting any order or booking
- [x] #3 Draft or credited invoices cannot receive payments; concurrent credit/payment operations cannot commit contradictory states
- [x] #4 Only admins can record or reverse invoice payments; existing order/course payment and refund tests still pass
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Extend the ledger owner constraint to exactly one order, registration or invoice; replace purchase-invoice validation with locked standalone invoice validation; add admin invoice record/reversal actions with paid_at and bank-transfer method. Generate the payment migration after TASK-168.9 schema generation, then verify ownership, lifecycle, balances, authorization and retained purchase flows.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented invoice-only bank-transfer ledger ownership with PostgreSQL three-owner constraint, admin record_invoice_payment/undo_invoice_payment actions and paid_at, locked lifecycle validation shared with credits, and fresh balances. No invoice receipt email hook. Meaningful coverage includes independent-connection credit/payment race, DB constraint rejection, dated partial payments and reversals, admin authorization, and retained purchase payment/refund/history flows. Validation: 164 focused payment tests passed.
<!-- SECTION:NOTES:END -->
