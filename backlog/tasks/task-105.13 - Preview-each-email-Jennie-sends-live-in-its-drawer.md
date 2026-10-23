---
id: TASK-105.13
title: 'Preview each email Jennie sends, live in its drawer'
status: in-progress
assignee: []
created_date: '2026-10-23 18:44'
updated_date: '2026-10-23 19:44'
labels: []
dependencies:
  - TASK-105.2
parent_task_id: TASK-105
type: feature
ordinal: 232000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie should see exactly what the customer will get, her message included, before it goes.

Every email Jennie triggers (tick box or menu item) shows a live preview in its drawer or dialog: subject and body built by the real `Edenflowers.Email` builder from the real order or booking and her message, updating as she types, never sent or queued by previewing. On a phone it sits below the form, collapsed. It renders in the customer's language, with a toggle to read it in Swedish. Attachments are named ("Attached: receipt.pdf", the doorstep photo) rather than generated. Automatic emails have no per-send preview: the admin Emails page covers them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every drawer or dialog that emails the customer shows the subject and body that would be sent
- [x] #2 The preview updates as Jennie types her message
- [x] #3 A toggle shows the same email in Swedish
- [x] #4 Attachments are listed by name
- [x] #5 Previewing never sends or queues an email
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Live preview in every drawer on the order and course pages (cancel, refund, record payment, fulfillment, and the email drawer for menu items), built by Edenflowers.Email.Preview. Still to do for AC1: the order form page (placing and editing) and the add-booking drawer, which have no saved record to build from yet. Planned alongside TASK-105.3.
<!-- SECTION:NOTES:END -->
