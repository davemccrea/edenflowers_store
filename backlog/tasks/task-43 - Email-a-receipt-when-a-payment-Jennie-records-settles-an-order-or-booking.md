---
id: TASK-43
title: Email a receipt when a payment Jennie records settles an order or booking
status: done
assignee: []
created_date: '2026-10-18 18:22'
updated_date: '2026-10-18 20:13'
labels:
  - spec
  - admin
  - customers
dependencies: []
priority: medium
type: feature
ordinal: 104000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Once a customer has paid in full they expect a receipt. Today Jennie has to remember to send one after recording a cash, transfer or invoice payment.

When the payment Jennie records brings the balance to 0, the payment form shows "Email a receipt", ticked by default, on orders and bookings alike. Ticked, the receipt email goes out as it does when she sends one by hand. A part payment doesn't show the checkbox.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Recording a payment that settles an order or booking offers 'Email a receipt', ticked
- [x] #2 Ticked, the customer gets the receipt; unticked, nothing is sent
- [x] #3 A part payment doesn't offer it
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
record_payment takes email_receipt?; Payments.Changes.EmailReceipt calls the resource's :email_receipt action after the payment commits when a positive payment leaves the balance at 0 (new :email_receipt on CourseRegistration clears skip_confirmation_email and resends the confirmation with the receipt). A failed send keeps the payment and flashes an error. Order panel shows the checkbox only while the amount equals the balance and the order has an email; booking rows show it on confirmed bookings, since they always record the full balance.
<!-- SECTION:NOTES:END -->
