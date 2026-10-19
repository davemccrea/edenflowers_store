---
id: TASK-61.1
title: >-
  Queue the fulfillment confirmation once, record its failure, and let Jennie
  send it again
status: done
assignee: []
created_date: '2026-10-19 07:59'
updated_date: '2026-10-19 08:06'
labels: []
dependencies: []
parent_task_id: TASK-61
type: feature
ordinal: 128000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** the fulfillment confirmation carries the most machinery of any email, and Jennie still can't send it after unticking "email the customer", or resend it to a corrected address.

Apply TASK-61's decisions to the fulfillment confirmation.

### Remove
- The `send_delivered_email` recovery scheduler and its `where @fulfillment_email_pending`, and the `@fulfillment_email_pending` expression with `Order.fulfillment_email_pending?/1`.
- `Edenflowers.Orders.FulfillmentEmail` (job-state inspection, status, retry) and `Orders.fulfillment_email_status/1`.
- `Changes.QueueFulfillmentEmail` and the `retry_fulfillment_email` action and code interface.
- The `skip_delivered_email` attribute. `mark_fulfilled`'s `email_customer?` argument now only decides whether a job is queued.
- On the order page: the `#order-confirmation-email` section, its status labels, the Retry button, the 5-second refresh timer and `:refresh_fulfillment_email`.

### Build
- Trigger: `scheduler_cron false`, `max_attempts 3`, `on_error :record_fulfillment_email_failure`. `mark_fulfilled` with `email_customer?` queues it after the fulfillment is saved. `SendDeliveredEmail` sends unconditionally when it runs (no pending check), sets `delivered_emailed_at` and `delivered_emailed_to` and clears `delivered_email_failed_at`.
- `record_fulfillment_email_failure`: accepts the `error` argument AshOban passes, sets `delivered_email_failed_at`. Logged as "Fulfillment confirmation failed".
- `email_fulfillment_confirmation`: admin action, valid on a placed, fulfilled order with a customer email; queues the job. Actions-menu item "Email confirmation" / "Resend confirmation" (after `delivered_emailed_at`), with `confirm_send`, and flash "Confirmation queued." It uses the photo choice stored on the order (`email_delivery_photo`).
- PubSub: publish the send and the failure on `["order", "fulfillment_email", :id]`; the order page subscribes, reloads, and flashes "Couldn't email the confirmation." on failure.
- The order page shows a warning near fulfillment while `delivered_email_failed_at` is set, with the photo/errors guidance the status section gave.

Generate the migration from the resource.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Marking an order fulfilled with "email the customer" queues one job; unticked queues none, and no scheduler sends it later
- [x] #2 A successful send logs "Fulfillment confirmation emailed" with the recipient and clears any recorded failure
- [x] #3 After the last attempt fails, the order records the failure, the log shows "Fulfillment confirmation failed", and an open order page flashes it without polling
- [x] #4 Jennie can email the confirmation from the actions menu after unticking it, after a failure, and again after a send
- [x] #5 FulfillmentEmail, QueueFulfillmentEmail, retry_fulfillment_email, skip_delivered_email, the scheduler and the status polling are gone
- [x] #6 Tests cover queueing, sending, final failure through on_error, resend, and the order page's live update; translations have no fuzzy entries
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Background email outcomes publish on ["order", "email", :id] rather than ["order", "fulfillment_email", :id], so TASK-61.2 can share the one topic; the page tells them apart by event (action name).
<!-- SECTION:NOTES:END -->
