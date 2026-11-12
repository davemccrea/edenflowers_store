---
id: TASK-193
title: Preview the customer email when recording a course booking's payment
status: done
assignee: []
created_date: '2026-11-12 06:22'
updated_date: '2026-11-12 07:10'
labels:
  - spec
  - admin
  - quick
dependencies: []
references:
  - docs/agents/ash-liveview-review.md
  - lib/edenflowers_web/features/admin/order_detail_live.ex
  - lib/edenflowers_web/features/admin/course_detail_live.ex
  - lib/edenflowers_web/features/admin/invoice_live.ex
  - lib/edenflowers_web/features/admin/payment_actions.ex
  - lib/edenflowers_web/features/admin/email_drawer.ex
  - lib/edenflowers_web/features/admin/drawer_preview.ex
  - lib/edenflowers_web/features/admin/drawers.ex
  - test/edenflowers_web/features/admin/balance_panel_test.exs
priority: low
type: feature
ordinal: 358000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When Jennie records a payment on a course booking, the drawer shows the email the customer will get, as it already does on an order.

**Why:** The order page previews the customer email both when recording a payment and when refunding. The course page previews only refunds, so Jennie records a booking payment without seeing what is sent.

## Problem

`course_detail_live.ex:274-293` builds the drawer preview only when `mode == :refund`. The order page builds one for both modes (`order_detail_live.ex:687-700`).

## Decisions (grilled 2026-11-12)

- The gap is an oversight: preview both on both pages.
- This task was first a plan to move the settlement, cancel and email drawers into one LiveComponent. A Ponytail review of the plan dropped that: the two pages' handlers are not copies (the course page hosts drawers for many bookings picked by id, the order page has one order), the files are the most-edited in the admin, and there is no bug behind it. Only the one real difference between the pages is fixed here.

## What to build

Build the settle-mode preview on the course page the way the order page does, when the settlement drawer opens and as the payment form changes. If recording a booking payment sends the customer no email, there is nothing to preview: stop and say so.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Opening a booking's settlement drawer to record a payment shows the preview of the email that recording it sends, and it updates as the form changes
- [x] #2 The refund preview on the course page still works
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The gap was smaller than described: the course page already previewed the receipt email as the payment form changed (PaymentActions.change_payment/4). Only opening the drawer dropped it, which showed when Jennie ticked the receipt box, closed the drawer and reopened it. open_settlement now builds the preview in both modes. Not checked in a browser.
<!-- SECTION:NOTES:END -->
