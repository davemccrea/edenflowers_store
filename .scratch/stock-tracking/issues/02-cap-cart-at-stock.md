# Customers can't add more than is in stock

Status: ready-for-agent

## Parent

`.scratch/stock-tracking/spec.md`

## What to build

Stop customers putting more of a tracked variant in their cart than is in stock, and show sold-out sizes honestly on the storefront.

Any change to a cart line's quantity (adding, incrementing, setting) is refused when it would take the line above the variant's stock, with an "Only N left" or "Sold out" message the customer sees. On the product page, a sold-out size is shown disabled and labelled "Sold out", the default selection skips sold-out sizes, and add-to-cart is disabled when every size is sold out. The checkout card drawer leaves out sold-out cards.

## Acceptance criteria

- [ ] Adding, incrementing or setting a cart line above a tracked variant's stock fails with "Only N left" (or "Sold out" at 0), and the customer sees it.
- [ ] Untracked variants have no cap.
- [ ] On the product page, sold-out sizes are disabled and labelled "Sold out", and aren't selected by default.
- [ ] When every size is sold out, the product page's add-to-cart is disabled.
- [ ] The card drawer doesn't offer sold-out cards.
- [ ] New strings are localised (en, fi, sv).

## Blocked by

- `01-online-orders-take-stock.md`
