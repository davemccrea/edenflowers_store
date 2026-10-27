---
id: TASK-127
title: Use one set of pricing rules for custom-order previews and saved orders
status: done
assignee: []
created_date: '2026-10-25 14:15'
updated_date: '2026-10-25 16:53'
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
- [x] #1 Catalogue/custom/card line pricing, promotion eligibility and cent rounding, fulfillment overrides/free delivery and historical-price/fee preservation have one authoritative implementation shared by quote and save.
- [x] #2 The quote is exposed as a domain operation without persisting orders, changing stock, sending emails or otherwise performing save-time side effects.
- [x] #3 Live totals and real email previews still work with incomplete forms; unrelated renders do not rerun pricing database lookups.
- [x] #4 Parity tests compare preview and saved totals/VAT/fees for new and edited orders, including promotion thresholds/rounding and unchanged historical pricing.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Grilled 2026-10-25: Order generic action quote_entered replaces EnteredPrice. It builds the real place_custom or edit changeset without submitting, shares PriceFulfillment's reprice decision and PopulateFromVariant's price snapshot, and evaluates the resources' own calc expressions in memory. OrderFormLive keeps price and preview in assigns. Out of scope: the change block shared by place_custom and edit.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Calculations.PromotionApplied and LineDiscount hold the promotion rules as expressions the resources and the quote both use. Form edits still reprice; other renders and events do not.
<!-- SECTION:NOTES:END -->
