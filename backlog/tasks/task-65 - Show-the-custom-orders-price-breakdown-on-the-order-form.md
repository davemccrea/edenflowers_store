---
id: TASK-65
title: Show the custom order's price breakdown on the order form
status: done
assignee: []
created_date: '2026-10-19 20:56'
updated_date: '2026-10-19 21:10'
labels:
  - spec
  - admin
dependencies: []
priority: high
type: feature
ordinal: 139000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie sees what the order costs while she enters it: each item, the card, delivery or pickup, VAT and the total, updated as she types, at the bottom of the form by Place order.

**Why:** A customer on the phone wants to know the price before they agree. Today the form shows only the delivery quote, and the total appears once the order is saved.

### What to build

- A price summary at the bottom of `order_form_live.ex`, next to the Payment section and Place order: one row per line (catalogue, custom, and the chosen card), the delivery or pickup fee (her own fee when she sets one), VAT, and the total.
- It follows the form's unsaved lines, not the saved order's. That also retires the `ponytail:` note on `charge/2`, which charges the delivery quote on the saved lines.
- On an edit of a paid order, also show what is already paid and the balance, as the order page's Payment section does.

### Open questions

- **Same numbers as saving:** the summary must match what `place_custom`/`edit` will save (free-delivery products, `PriceFulfillment`, VAT per rate). Either price the form's lines with the domain's own functions, or run the action's pricing without saving. Pick one that can't drift from the saved order.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The form shows each line, the fulfillment fee, VAT and the total before the order is saved
- [x] #2 The summary updates as items, quantities, prices, the card, the option, the address or her own fee change
- [x] #3 The total shown equals the total of the order once saved
- [x] #4 Editing a paid order also shows what is paid and the balance
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Priced by Orders.EnteredPrice from the params the form submits, with the domain's own rules: lines as LineItem :enter and EnterCardLine price them, the fee as PriceFulfillment and fee_for_cart charge it (an edit that leaves the option, address and own fee alone keeps the order's fee), VAT by Vat.compute_breakdown. The address is priced by the quote the form already looked up, so nothing is geocoded per keystroke. Tests check the shown total, VAT and fee equal the saved order's. The summary sits above Payment, so the payment choice stays last before Place order. money_row moved to Admin.Components for the order page and the form.
<!-- SECTION:NOTES:END -->
