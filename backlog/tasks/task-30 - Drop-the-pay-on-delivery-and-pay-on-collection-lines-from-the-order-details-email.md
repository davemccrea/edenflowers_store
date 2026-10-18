---
id: TASK-30
title: >-
  Drop the pay-on-delivery and pay-on-collection lines from the order-details
  email
status: ready-for-agent
assignee: []
created_date: '2026-10-18 18:22'
labels:
  - spec
  - customers
  - quick
dependencies: []
priority: low
type: bug
ordinal: 85000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie arranges payment for an unpaid custom order herself. Telling the customer they can pay at the door promises something she may not offer.

`order_details.text.eex` ends with "You can pay when the flowers are delivered." or "You can pay when you collect the flowers." when the order has a balance and no payment link. Remove both branches: the email shows the balance and nothing else. Clear the msgids from the .pot and the en/fi/sv .po files.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The order-details email for an unpaid order without a payment link shows the balance and no line about when to pay
- [ ] #2 Neither sentence is left in the .pot or the en/fi/sv .po files
<!-- AC:END -->
