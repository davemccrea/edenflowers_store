# Refuse cancelling or editing an order that has moved on since it was loaded

Status: ready-for-agent
Type: bug

## Problem

`Order.cancel`, `cancel_by_customer` and `edit` are `require_atomic? false` (they call Stripe and run `AdjustStock` after the write). So `validate attribute_equals(:state, :placed)` and `validate attribute_equals(:fulfillment_status, :pending)` check the record passed in, not the row.

`Admin.OrderDetailLive` passes `socket.assigns.order`, loaded when Jennie opened the page:

1. Jennie has the order page open.
2. The customer cancels from their account. `AdjustStock` returns the stock.
3. Jennie clicks Cancel. Her copy still reads pending, so the validations pass.
4. The order is cancelled again and `AdjustStock` returns the same stock a second time.

`edit` the same way: Jennie can edit, and take and return stock for, an order that was cancelled or fulfilled since she opened the form.

`mark_fulfilled` is atomic, so its validation already runs against the row.

## What to build

- `change filter expr(state == :placed and fulfillment_status == :pending)` on `cancel`, `cancel_by_customer` and `edit`, the idiom `CreateOccurrence` and `Token.expunge_expired` use. The UPDATE then matches no row, Ash returns `Ash.Error.Changes.StaleRecord`, and the transaction rolls back before `AdjustStock`'s after-action runs. Keep the existing validations: they give the readable message in the ordinary case.
- `CancelOpenPaymentIntent` runs after the transaction; check it does nothing when the action failed.
- `cancel_by_customer`: `RefundInFull` refunds in `before_transaction`, so the filter can't stop a refund already sent. The account page loads the order just before cancelling, so the window is small; the filter still stops the cancel overwriting a fulfilled order. Leave the refund ordering as it is (it guarantees the order is never cancelled while holding the customer's money), but log an error when the refund succeeded and the write then came back stale, so Jennie hears of it (ADR 0002).
- `Admin.OrderDetailLive` and `Admin.OrderFormLive`: on a stale error, reload the order and flash that it changed meanwhile, instead of the generic "Could not cancel the order."

## Tests

- Cancelling an order through a stale struct after it was cancelled elsewhere fails, and stock is returned only once.
- Cancelling through a stale struct after it was fulfilled fails and leaves it fulfilled.
- Editing through a stale struct after a cancel fails and changes neither the order nor stock.
- The ordinary cancel, customer cancel and edit tests pass unchanged.

## Acceptance criteria

- [ ] Every case above passes
- [ ] The existing suite passes

## Comments
