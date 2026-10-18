---
id: TASK-33.2
title: 'Save a custom order without the recipient''s phone, and flag it'
status: ready-for-agent
assignee: []
created_date: '2026-10-18 18:22'
labels: []
dependencies: []
parent_task_id: TASK-33
type: feature
ordinal: 90000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** If Jennie forgets to ask for the recipient's phone, the form refuses to save and she loses the order she's taking. The phone is needed for the delivery, not for the order to exist.

Drop the `validate present(:recipient_phone_number)` for deliveries on the custom order actions. The name, a phone or an email, the method and the date stay required. A delivery with no recipient phone shows a "Missing recipient phone" warning on the order page and on its row in the fulfillments list.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A custom delivery order saves without a recipient phone
- [ ] #2 Such an order shows 'Missing recipient phone' on the order page and the fulfillments list
- [ ] #3 Customer name, a contact, method and date are still required
<!-- AC:END -->
