---
id: TASK-17.3
title: Share Jennie's payment controls between the order page and the courses page
status: done
assignee: []
created_date: '2026-10-18 03:08'
updated_date: '2026-10-20 18:55'
labels: []
dependencies:
  - TASK-17.1
parent_task_id: TASK-17
type: refactor
ordinal: 50000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The order page and the courses page each handle payments, refunds and payment links with their own messages and errors, so they drift apart.

### Problem

`Admin.OrderDetailLive` and `Admin.CoursesLive` each handle `record_payment`, `undo_payment`, `refund_with_stripe`, `open_payment_link` and `email_payment_link` against a payable, with their own flash messages and error handling. The order page also renders the payments list, money rows and payment-link buttons, which the courses page shows its own way for each booking.

### The idea

The handlers call `Payable` actions that share names (after `TASK-17.1`), so they can live once: a LiveComponent for "the money on this record" (payments list, record and undo, refund, payment link), mounted on the order page and in each booking's row or drawer. Each page keeps its own layout around it.

### To decide

- The courses page manages many bookings on one page, where the order page has one record. Check whether one component reads well in both, or only the handlers should be shared.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
EdenflowersWeb.Admin.PaymentActions holds record_payment, undo_payment, refund_with_stripe, open_payment_link and email_payment_link, calling the shared Payable actions by name and returning the flash. payment_error/1 and refund_message/1 moved there from Admin.Components. Each page keeps its own layout and reload.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-18 12:28

---

Decided: share the handlers, not a LiveComponent. The courses page keeps each booking's payment controls in its actions menu next to seat and cancel actions, and reloads every course after one, so a per-booking component would need its own parent messaging and split the menu.

---

author: @claude
created: 2026-10-20 18:55

---

The drawer this mentions now exists: TASK-60 and TASK-79 (3d0fd5ad) give both pages a settlement drawer built on the shared admin_drawer, record_payment_form and goodwill_refund_form. The handlers stay per page, because the course refund sets an amount to hand back while the order refund records a minus payment.

---
<!-- COMMENTS:END -->
