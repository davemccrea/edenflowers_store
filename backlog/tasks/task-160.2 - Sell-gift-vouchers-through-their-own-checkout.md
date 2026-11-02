---
id: TASK-160.2
title: Sell gift vouchers through their own checkout
status: ready-for-agent
assignee: []
created_date: '2026-11-01 17:32'
labels: []
dependencies:
  - TASK-160.1
parent_task_id: TASK-160
type: feature
ordinal: 308000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Christmas buyers need to buy a voucher online by 1.12 without going through flower delivery steps.

- A one-page voucher checkout built on an Order with a voucher line and the existing Stripe PaymentIntent flow: amount 20-200 EUR in steps of 10, recipient name, message, buyer email, card.
- Placing the order creates the voucher (expiry one year) and emails a Typst PDF (amount, code, expiry, recipient, message; sv and fi; receipts' theme).
- Checkbox 'collect a printed card at Minimossen': the email says it's ready from the next opening day, and the order shows a badge for Jennie to print it.
- A link to the voucher checkout from the store.
- Terms of sale: a short voucher section (valid one year, refundable while unspent, no cash for a part-spent voucher), sv/fi/en.
- Cancelling an unspent voucher's order refunds it and stops the voucher.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A buyer can buy a voucher online and receives its PDF by email
- [ ] #2 Choosing to collect shows a badge on the order and says so in the email
- [ ] #3 The terms of sale describe vouchers
<!-- AC:END -->
