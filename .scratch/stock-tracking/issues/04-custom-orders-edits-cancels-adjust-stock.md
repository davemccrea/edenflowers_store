# Custom Orders, edits and cancels adjust stock

Status: ready-for-agent

## Parent

`.scratch/stock-tracking/spec.md`

## What to build

Keep the count right for everything Jennie does in the admin, using the shared stock change from issue 01.

Saving a Custom Order takes stock for its tracked lines. Cancelling an open order puts its tracked lines back. Editing an open order puts the old lines back, then takes the new ones: the same change run twice, not a calculated difference. None of these are ever blocked or logged, since Jennie knows the shelf better than the count does. The count still floors at 0. Occurrences never touch stock.

## Acceptance criteria

- [ ] Saving a Custom Order lowers stock for its tracked lines, and is never blocked even when it exceeds the count (which floors at 0, with no error logged).
- [ ] Cancelling an open order (Online or Custom) puts its tracked lines back.
- [ ] Editing an open order nets out correctly: a removed line comes back, 1 → 3 takes 2 more, and a swapped variant moves stock between the two.
- [ ] Subscription Occurrences never change stock.
- [ ] Fulfilled orders can't be edited or cancelled, so their stock never moves (existing guard, covered by a test).

## Blocked by

- `01-online-orders-take-stock.md`
