---
id: TASK-182
title: 'Let Jennie show, hide and order store categories from the admin'
status: needs-triage
assignee: []
created_date: '2026-11-07 08:07'
labels:
  - spec
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 347000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie can set each product category's visibility (public, draft, hidden) and its store order from the admin, without a developer.

**Why:** Today showing, hiding or reordering a category takes a seed or a production rpc command, so Jennie can't prepare a seasonal category and publish it herself.

ProductCategory already has `visibility` and `position` (lib/edenflowers/catalog/product_category.ex); the store reads them. What's missing is admin UI.

Open questions:
- A new admin categories page, or edit controls on the products page?
- Should she also edit name, description and translations, or create new categories?
- How to reorder: drag, or up/down buttons (admin PWA is iOS only)?
- Where does the Gift voucher link sit if Bouquets is hidden? It currently goes after Bouquets, or at the end without it.
<!-- SECTION:DESCRIPTION:END -->
