---
id: TASK-100
title: Take Instagram orders without an email or phone
status: done
assignee: []
created_date: '2026-10-22 20:20'
updated_date: '2026-10-22 20:20'
labels:
  - admin
  - customers
  - quick
dependencies: []
priority: medium
type: feature
ordinal: 203000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie can save a custom order with only the customer's Instagram handle, and an order with no email asks for one on its payment page so the customer gets a receipt.

**Why:** Many orders arrive by Instagram DM with no email or phone. The custom order form refused to save them, and a customer paying such an order's link got no receipt.

Decisions: the handle lives on the order only (no prefill, not on the user), stored as typed and shown as an ig.me DM link. The pay page's email is required, and saving it links the order to that customer as the custom form does. It never replaces an email already on the order.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A custom order saves with only an Instagram handle as contact
- [x] #2 The order page links the handle to an Instagram DM, and admin search finds it
- [x] #3 The payment page of an order without an email requires one before paying, saves it and links the customer
- [x] #4 The payment page never replaces an email already on the order
<!-- AC:END -->
