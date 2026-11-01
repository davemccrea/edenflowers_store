---
id: TASK-160.3
title: Sell vouchers and record voucher payments in admin
status: ready-for-agent
assignee: []
created_date: '2026-11-01 17:32'
labels: []
dependencies:
  - TASK-160.1
parent_task_id: TASK-160
type: feature
ordinal: 309000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie sells in the shop and takes many orders by phone, so vouchers have to work on Custom Orders and manual course bookings too.

- A voucher can be added to a Custom Order with an amount and recipient. Placing it creates the voucher, and Jennie can print its PDF.
- Recording a payment offers Voucher: Jennie enters the code, and it pays min(what's left, Balance) like checkout.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Jennie can sell a voucher on a Custom Order and print its PDF
- [ ] #2 Jennie can pay a Custom Order or course booking with a voucher code
<!-- AC:END -->
