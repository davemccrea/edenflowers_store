---
id: TASK-127
title: Use one set of pricing rules for custom-order previews and saved orders
status: needs-triage
assignee: []
created_date: '2026-10-25 14:15'
labels:
  - spec
  - admin
  - developers
dependencies: []
references:
  - lib/edenflowers/orders/entered_price.ex
  - lib/edenflowers/orders/line_item.ex
  - lib/edenflowers/orders/order.ex
  - lib/edenflowers/orders/changes/price_fulfillment.ex
  - lib/edenflowers_web/features/admin/order_form_live.ex
  - test/edenflowers/orders/entered_price_test.exs
priority: medium
type: refactor
ordinal: 249000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The price and email preview for a Custom Order are derived from the same domain pricing rules used to save it.

**Why:** Jennie quotes the preview price to customers. EnteredPrice repeats promotion, historical-price and fulfillment decisions, so a pricing change must update two implementations and keep their results aligned.

Review evidence: Orders.EnteredPrice manually rebuilds line totals and promotion eligibility/rounding and reproduces PriceFulfillment's fee-preservation decisions. Its comments explicitly reference the corresponding resource rules. OrderFormLive calls it from render, causing variant/tax/fulfillment lookups to repeat on rendering.

Expose a side-effect-free quote operation through Ash and share the underlying pricing rules with the save path. Merely wrapping EnteredPrice in a generic action is not enough: remove the independent formulas/decisions. Reuse existing calculations and pure pricing code where practical, without adding an elaborate pricing engine or performing real saves/refunds/emails to obtain a preview.

Preserve live price and customer-email previews required by ADR-0006; incomplete forms may still show partial prices, and historical prices/fees must remain stable when an edit leaves the relevant fields unchanged. Retain the existing preview-versus-saved parity tests. Arrange the page so unrelated renders do not repeatedly run the pricing database lookups.

Triage the smallest shared pricing seam before implementation; this is not permission for a wholesale order-model rewrite.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Catalogue/custom/card line pricing, promotion eligibility and cent rounding, fulfillment overrides/free delivery and historical-price/fee preservation have one authoritative implementation shared by quote and save.
- [ ] #2 The quote is exposed as a domain operation without persisting orders, changing stock, sending emails or otherwise performing save-time side effects.
- [ ] #3 Live totals and real email previews still work with incomplete forms; unrelated renders do not rerun pricing database lookups.
- [ ] #4 Parity tests compare preview and saved totals/VAT/fees for new and edited orders, including promotion thresholds/rounding and unchanged historical pricing.
<!-- AC:END -->
