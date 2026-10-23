---
id: TASK-105.13
title: 'Preview each email Jennie sends, live in its drawer'
status: ready-for-agent
assignee: []
created_date: '2026-10-23 18:44'
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
- [ ] #2 The preview updates as Jennie types her message
- [ ] #3 A toggle shows the same email in Swedish
- [ ] #4 Attachments are listed by name
- [ ] #5 Previewing never sends or queues an email
<!-- AC:END -->
