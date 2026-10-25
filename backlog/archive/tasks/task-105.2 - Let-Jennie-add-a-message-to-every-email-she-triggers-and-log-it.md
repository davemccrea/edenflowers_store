---
id: TASK-105.2
title: 'Let Jennie add a message to every email she triggers, and log it'
status: done
assignee: []
created_date: '2026-10-23 18:42'
updated_date: '2026-10-23 19:38'
labels: []
dependencies: []
parent_task_id: TASK-105
type: feature
ordinal: 215000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** One way to add her own words is easier to learn than a reason field here and a note field there, and the order log shows what the customer was told.

Every action that emails the customer on Jennie's behalf gets the tick box and a message box beside it. The message renders after the email's opening line about what happened, before the totals, refund lines or link. The cancellation reason (orders and bookings) and the refund note become this message. The order log records the email sent and the message with it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each email Jennie triggers has a tick box and an optional message box in its drawer or dialog
- [x] #2 The message appears after the line saying what happened and before the details
- [x] #3 The cancellation reason and refund note are the message, with no separate field left behind
- [x] #4 The order log shows which email went and the message sent with it
<!-- AC:END -->
