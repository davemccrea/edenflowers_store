---
id: TASK-54
title: Ask whether to send email when marking an order as fulfilled
status: ready-for-agent
assignee: []
created_date: '2026-10-18 20:18'
labels:
  - spec
  - admin
  - customers
  - quick
dependencies: []
priority: medium
type: feature
ordinal: 120000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Let Jennie choose whether to send the customer an email when using Mark as fulfilled, with sending enabled by default.

**Why:** Jennie can record an order as fulfilled without sending an unwanted customer email, while keeping the usual notification as the default.

The Mark as fulfilled flow must ask whether to send the fulfillment email before completing the action. Default the choice to yes each time the flow is opened. Choosing no must still mark the order as fulfilled without sending the email.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Mark as fulfilled asks whether to send the customer a fulfillment email before completing the action.
- [ ] #2 The send-email choice defaults to yes each time the flow is opened.
- [ ] #3 Confirming with yes marks the order as fulfilled and sends the usual fulfillment email.
- [ ] #4 Confirming with no marks the order as fulfilled without sending the fulfillment email.
<!-- AC:END -->
