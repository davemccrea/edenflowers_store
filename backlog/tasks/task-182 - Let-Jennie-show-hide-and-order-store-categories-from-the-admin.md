---
id: TASK-182
title: 'Let Jennie show, hide and order store categories from the admin'
status: done
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

Decisions (grilled 2026-11-11):
- Own page at /admin/products/categories, opened from a 'Categories' button on the Products page. Not in the main nav.
- Only visibility and order. Names, descriptions, translations, creating and deleting stay with a developer.
- Up/down buttons save at once and renumber every category, Hidden and Draft ones included, in one list.
- Public, Hidden and Draft are all offered, each explained in one line, and save at once. Making a category with published products a Draft asks first and names how many products leave the store.
- The store's Gift voucher link always sits last in the ribbon.
<!-- SECTION:DESCRIPTION:END -->
