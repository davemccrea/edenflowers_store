# Payment step blocks lines over stock

Status: ready-for-agent

## Parent

`.scratch/stock-tracking/spec.md`

## What to build

A cart can go over stock after it was filled, when someone else buys the last units. Before the customer is charged, the checkout payment step checks every line against the current stock. While any line is over, no PaymentIntent is created and the step says which line and how many are left. Lines are never changed or removed automatically; the customer fixes the cart and carries on.

## Acceptance criteria

- [ ] With a line over the current stock, the payment step creates no PaymentIntent and names the line ("Only N left" / "Sold out").
- [ ] Once the customer fixes the line, payment goes ahead as normal.
- [ ] Cart lines are never changed or removed automatically.
- [ ] Carts with only untracked variants behave exactly as before.
- [ ] New strings are localised (en, fi, sv).

## Blocked by

- `01-online-orders-take-stock.md`
