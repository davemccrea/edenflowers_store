---
id: TASK-27
title: Share one list of an order's promotion fields
status: done
assignee: []
created_date: '2026-10-18 11:35'
updated_date: '2026-10-18 17:42'
labels:
  - spec
  - developers
  - quick
dependencies: []
priority: low
type: refactor
ordinal: 82000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
An order's promotion fields are listed in one place, so clearing a promotion can't leave half of one behind

**Why:** `clear_promotion` and `ResetCheckout` each listed all five promotion attributes, and missing one in either leaves an order with half a promotion.

### Decision

The embedded `promotion_snapshot` idea was dropped: only three places write these fields, and it would need a data migration plus reaching into an embedded map from the `discount_rate` expressions in `Order` and `LineItem`. Instead `Changes.ClearPromotionFields` holds the list (like `ClearDeliveryFields`), used by `clear_promotion` and `ResetCheckout`. `ApplyPromotion` still sets each field explicitly, as it copies each one from the promotion.
<!-- SECTION:DESCRIPTION:END -->
