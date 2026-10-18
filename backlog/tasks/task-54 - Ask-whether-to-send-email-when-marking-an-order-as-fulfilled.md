---
id: TASK-54
title: Ask whether to send email when marking an order as fulfilled
status: done
assignee: []
created_date: '2026-10-18 20:18'
updated_date: '2026-10-18 20:55'
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
- [x] #1 Mark as fulfilled asks whether to send the customer a fulfillment email before completing the action.
- [x] #2 The send-email choice defaults to yes each time the flow is opened.
- [x] #3 Confirming with yes marks the order as fulfilled and sends the usual fulfillment email.
- [x] #4 Confirming with no marks the order as fulfilled without sending the fulfillment email.
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-18 20:43

---

Mark as fulfilled now opens a confirm form with an 'Email the customer' checkbox, ticked each time it opens. The order records the choice as skip_delivered_email, which keeps the delivered-email trigger from ever firing, so the scheduler can't send it later either. The delivery flow's confirm widget now serves pickups too, so both go through one form (renamed from delivery to fulfillment).

---

author: @claude
created: 2026-10-18 20:52

---

Follow-up: the delivered-email change now re-checks skip_delivered_email itself, as SendConfirmationEmail does, so the order's choice holds for the worker and any direct caller, not only the trigger's where.

---

author: @claude
created: 2026-10-18 20:55

---

Refined to Ash's declarative form: the :send_delivered_email action gates Changes.SendDeliveredEmail with where: [attribute_equals(:skip_delivered_email, false)] rather than an if inside the change.

---
<!-- COMMENTS:END -->
