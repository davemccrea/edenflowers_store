---
id: TASK-33.1
title: 'Ask whether a custom order is a gift, as checkout does'
status: done
assignee: []
created_date: '2026-10-18 18:22'
updated_date: '2026-10-18 18:53'
labels: []
dependencies: []
parent_task_id: TASK-33
type: feature
ordinal: 89000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Checkout asks gift or not, and only then asks for a recipient and a card. The custom form shows recipient fields with a "leave blank" hint instead, so Jennie has to remember what a blank means.

Add the gift toggle to `order_form_live.ex`, matching checkout's wording. Not a gift: recipient name, phone and card message are hidden and cleared. A gift: they show, and `gift` is set on the order. Drop the "Leave the recipient blank…" description.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The form has a gift / not a gift choice like checkout's
- [x] #2 Recipient and card fields only show for a gift, and switching to not a gift clears them
- [x] #3 The order's gift attribute matches the choice
<!-- AC:END -->
