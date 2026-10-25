---
id: TASK-19.1
title: Refuse cancelling or editing an order that has moved on since it was loaded
status: done
assignee: []
created_date: '2026-10-18 03:24'
updated_date: '2026-10-18 09:29'
labels:
  - quick
dependencies: []
parent_task_id: TASK-19
type: bug
ordinal: 61000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** An order cancelled or fulfilled while Jennie's page was open can be cancelled or edited again, returning its stock twice.

### Problem

`Order.cancel`, `cancel_by_customer` and `edit` are `require_atomic? false` (they call Stripe and run `AdjustStock` after the write). So `validate attribute_equals(:state, :placed)` and `validate attribute_equals(:fulfillment_status, :pending)` check the record passed in, not the row.

`Admin.OrderDetailLive` passes `socket.assigns.order`, loaded when Jennie opened the page:

1. Jennie has the order page open.
2. The customer cancels from their account. `AdjustStock` returns the stock.
3. Jennie clicks Cancel. Her copy still reads pending, so the validations pass.
4. The order is cancelled again and `AdjustStock` returns the same stock a second time.

`edit` the same way: Jennie can edit, and take and return stock for, an order that was cancelled or fulfilled since she opened the form.

`mark_fulfilled` is atomic, so its validation already runs against the row.

### What to build

- `change filter expr(state == :placed and fulfillment_status == :pending)` on `cancel`, `cancel_by_customer` and `edit`, the idiom `CreateOccurrence` uses. The UPDATE then matches no row, Ash returns `Ash.Error.Changes.StaleRecord`, and the transaction rolls back before `AdjustStock`'s after-action runs. Keep the existing validations: they give the readable message in the ordinary case.
- `Admin.OrderDetailLive` cancel: on any error, reload the order. If it is no longer pending, flash that it changed meanwhile; otherwise keep "Could not cancel the order." The cancel button hides itself on the reloaded order.
- `Admin.OrderFormLive` save: on an error, if the reloaded order is no longer pending, flash that it changed meanwhile and navigate to the order page, instead of "Check the fields marked below" with nothing marked.

### Decided not to do

- `CancelOpenPaymentIntent` already acts only on `{:ok, record}`, so a stale write cancels no PaymentIntent.
- `cancel_by_customer` refunds in `before_transaction`, so the filter can't stop a refund already sent. No extra logging: `CancellableByCustomer` re-reads the row, so the window is one Stripe call; only a fulfil landing in it is wrong; and the refund still shows on the order through the `refund.created` webhook (ADR 0002).

### Tests

- Cancelling an order through a stale struct after it was cancelled elsewhere fails, and stock is returned only once.
- Cancelling through a stale struct after it was fulfilled fails and leaves it fulfilled.
- Editing through a stale struct after a cancel fails and changes neither the order nor stock.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every case above passes
- [x] #2 The existing suite passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Filter on cancel, cancel_by_customer and edit. Admin detail page reloads and flashes when the cancel lost the race; the edit form flashes and goes back to the order page.
<!-- SECTION:NOTES:END -->
