---
id: TASK-173.4
title: Record customer bank transfers on their invoices
status: ready-for-agent
assignee: []
created_date: '2026-11-04 17:44'
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

- The same sync also reads booked credit transactions. One whose reference number (ignoring spaces) equals an issued, open invoice's `reference_number` is recorded through `Invoice.record_payment` with the transaction's amount and booking date, whatever the amount.
- Payment gains the bank transaction ID (nullable, unique identity) so a transaction seen on two runs is recorded once. Generate the migration with `mix ash.codegen`.
- No email to the customer, no notification to Jennie, nothing in admin marking it as from the bank.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A booked transfer with an open invoice's reference number is recorded as its payment with its amount and booking date
- [ ] #2 The same bank transaction seen again is not recorded twice
- [ ] #3 Transfers matching no open invoice are ignored
<!-- AC:END -->
