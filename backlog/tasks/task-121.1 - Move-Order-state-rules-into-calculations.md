---
id: TASK-121.1
title: Move Order state rules into calculations
status: done
assignee: []
created_date: '2026-10-25 10:08'
updated_date: '2026-10-25 13:11'
labels: []
dependencies: []
parent_task_id: TASK-121
type: refactor
ordinal: 241000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** order_detail_live, order_form_live, orders_live and account_live each re-derive what an order is or allows.

Add to Order: customer_status (enum), upcoming?, overdue?, open?, deletable?, editable?, payment_reminder_sendable?. Validations.Deletable, :edit and :send_payment_reminder use them. The web reads them in place of status_label's date logic, upcoming_order?, overdue?, open_orders, cancel_unavailable, deletable?, edit_mode/closed_meanwhile? and reminder?. orders_live's search filter reuses the :search read's expression.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Order exposes customer_status, upcoming?, overdue?, open?, deletable?, editable? and payment_reminder_sendable?
- [x] #2 The listed web helpers read those calculations and no longer match on status fields
- [x] #3 Deletable, :edit and :send_payment_reminder are guarded by the same calculations
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Also added fulfillable?, receipt_available? and matches?(term). A shared Validations.Holds guards :edit, :mark_fulfilled and :send_payment_reminder with the calculation the admin uses to offer them. Status labels (cancel/receipt reasons) stay in the web as presentation.

Review follow-up: confirmation-page receipt links now read receipt_available?; fully refunded orders cannot be sent payment reminders; order-details and fulfillment-confirmation eligibility are calculations used by both the admin and actions. Holds supports atomic validation. Added regression tests.
<!-- SECTION:NOTES:END -->
