---
id: TASK-43
title: Email a receipt when a payment Jennie records settles an order or booking
status: ready-for-agent
assignee: []
created_date: '2026-10-18 18:22'
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
- [ ] #1 Recording a payment that settles an order or booking offers 'Email a receipt', ticked
- [ ] #2 Ticked, the customer gets the receipt; unticked, nothing is sent
- [ ] #3 A part payment doesn't offer it
<!-- AC:END -->
