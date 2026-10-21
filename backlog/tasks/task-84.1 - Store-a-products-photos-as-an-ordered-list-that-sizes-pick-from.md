---
id: TASK-84.1
title: Store a product's photos as an ordered list that sizes pick from
status: ready-for-agent
assignee: []
created_date: '2026-10-21 15:35'
updated_date: '2026-10-21 15:39'
labels: []
dependencies: []
parent_task_id: TASK-84
type: feature
ordinal: 170000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** everything else in TASK-84 reads and writes this; the rules about which photo a size shows belong in the Catalog resources, not in the form or the pages.

Already in place (groundwork commit, 2026-10-21): a size's photo is optional and the ProductVariant `photo_slug` calculation falls back to the product photo; the store page, card picker, admin order form and line item snapshots read `photo_slug`.

### What to build

- **Product:** replace `image_slug` with `photo_slugs`, `{:array, :string}, constraints: [min_length: 1, max_length: 8]`. Order is display order.
- **Product calculation** `main_photo_slug`: `expr(at(photo_slugs, 0))`. Every reader of the main photo (category cards, admin product list, social previews, JSON-LD, seeds) uses it; nobody indexes the list.
- **ProductVariant:** rename the optional attribute `image_slug` to `own_photo_slug`. `photo_slug` becomes `expr(own_photo_slug || product.main_photo_slug)`.
- **Validation on Product create and update:** each submitted size's `own_photo_slug` is nil or one of `photo_slugs`. Both are in the one changeset, so the size doesn't re-read its product.
- **Change on Product update:** sizes whose `own_photo_slug` is no longer in `photo_slugs` are cleared in one bulk update. Callers never do this.
- **Loading:** read actions whose callers show a photo load it with `prepare build(load: ...)`, as `for_card_drawer` does, rather than each page passing `load:`.
- Generate the migration with `mix ash.codegen`; update the seeds. Courses keep `image_slug`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Saving a product with no photos or more than 8 fails with a field error
- [ ] #2 Saving a size whose photo isn't one of its product's fails with a field error
- [ ] #3 Removing a product photo that a size uses leaves that size showing the main photo
- [ ] #4 Every place that showed the product photo shows the first photo in the list
<!-- AC:END -->
