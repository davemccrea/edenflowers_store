---
id: TASK-5.1
title: Charge a same-day delivery fee
status: done
assignee: []
created_date: '2026-10-10 14:30'
labels:
  - wontfix
dependencies: []
parent_task_id: TASK-5
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

Let each fulfillment option carry a same-day surcharge (e.g. €5) that is added when the customer picks today as the fulfillment date, and show it as its own line wherever the order's price is shown.

Same-day is already a per-option setting (`same_day` + `order_deadline`); this adds the price. It is an add-on to the existing option, not a separate "Express" fulfillment option, so distance pricing and the calendar stay shared.

- **Setting:** a `same_day_fee` on the fulfillment option (non-negative, whole cents, default 0), editable in the admin option form next to the same-day checkbox and deadline, and accepted by `:update_pricing`. Shown in the option's price summary on `/admin/fulfillments` when non-zero. 0 means same-day is free (expected for pickup).
- **Order:** the fee is stored on the order in its own field when the fulfillment date is set to today, and cleared when the date moves off today, the same way `quoted_fulfillment_fee` freezes the delivery fee. It is not folded into `quoted_fulfillment_fee`, so it can be shown on its own line and later price changes don't alter placed orders.
- **Free delivery:** free-delivery products don't waive it. The surcharge pays for speed, not distance.
- **Jennie's override:** when she sets her own fee on an order (`fulfillment_fee_override`), that is the whole fulfillment charge and no same-day fee is added.
- **Subscriptions:** occurrences are never charged it.
- **Totals:** included in `grand_total`, the Stripe amount and VAT (at the fulfillment option's tax rate, like the delivery fee).
- **Shown as a separate "Same-day delivery" line** in:
  - the checkout cart summary, below the Delivery line
  - the pay page
  - the order page / receipt
  - the order confirmation email
  - the admin order detail page and order log

```
Subtotal              €45.00
Delivery · 7 km        €3.00
Same-day delivery      €5.00
──────────────────────────────
Total                 €53.00
```
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Admin can set the same-day fee per option; invalid amounts (negative, sub-cent) show a field error
- [ ] #2 Picking today on an option with a fee adds it to the checkout summary as its own line, and the total and Stripe amount include it
- [ ] #3 Picking another day shows no same-day line and charges nothing extra
- [ ] #4 An order with free delivery still pays the same-day fee
- [ ] #5 An order with a fulfillment fee override pays only the override
- [ ] #6 Changing the option's fee after an order is placed doesn't change that order's total
- [ ] #7 Moving a placed order's date onto or off today (admin edit) adds or removes the fee
- [ ] #8 The line appears on the pay page, receipt, confirmation email and admin order detail
- [ ] #9 VAT on the fee is included in the order's VAT total
- [ ] #10 User-facing strings use `~t` and are translated
<!-- AC:END -->
