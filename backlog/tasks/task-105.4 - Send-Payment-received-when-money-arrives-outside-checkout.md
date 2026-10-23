---
id: TASK-105.4
title: Send Payment received when money arrives outside checkout
status: ready-for-agent
assignee: []
created_date: '2026-10-23 18:42'
labels: []
dependencies:
  - TASK-105.2
parent_task_id: TASK-105
type: feature
ordinal: 217000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** "Thank you for your order" is wrong for someone who ordered by phone two weeks ago and has just paid the link.

Payment received replaces the order receipt for a paid payment link, a top-up after an edit and the receipt Jennie sends for a payment she recorded. Subject "Payment received for your order for <date>" (bookings: the course and date). "I've received your payment of <amount>. Your receipt is attached." plus the totals block. Neutral wording, so it also serves a booking paid after the course (no separate course receipt). No payment link even if something is still owed. Recording a payment gets an "Email the customer a receipt" tick box, unticked.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Paying an order's or booking's payment link sends Payment received, not the order receipt or booking confirmation
- [ ] #2 Recording a payment offers the email, unticked
- [ ] #3 The order menu's receipt item sends Payment received
- [ ] #4 Previews on the admin Emails page cover every version, and the new copy is translated in en, fi and sv
<!-- AC:END -->
