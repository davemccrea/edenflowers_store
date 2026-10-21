---
id: TASK-84
title: Give each product a photo gallery that its sizes pick from
status: done
assignee: []
created_date: '2026-10-21 15:35'
updated_date: '2026-10-21 15:50'
labels:
  - spec
  - customers
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 169000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A product has up to 8 photos; customers browse them on the product page, and each size can show one of them.

**Why:** Jennie can show a bouquet from more than one angle, and a size photo is picked from the product's photos instead of uploaded on its own. Per-size uploads are what crashed the product form on 2026-10-21 (BadMapError in `PhotoUpload.photo_input`, a size whose upload was never allowed; patched in the groundwork commit 0cbfecf8), and they go away here.

Works the way Shopify does: photos belong to the product, sizes point at one.

### Decisions (grilled 2026-10-21)

- **Storage:** an ordered list `photo_slugs` on Product; the first is the main photo, read through the `main_photo_slug` calculation. At least 1, at most 8.
- **Sizes:** a size optionally picks one of its product's photos (`own_photo_slug`). With none it shows the main photo, read through the ProductVariant `photo_slug` calculation. A picked photo must be one of the product's.
- **Removing a photo** a size uses sends that size back to the main photo, done in the product's update, not by callers. Removed files stay on disk.
- **Order:** a "Make main" button moves a photo to the front; the others keep upload order. No drag and drop.
- **Admin form:** one gallery area takes up to 8 photos, each stored as soon as its upload finishes, so sizes can pick it straight away. An abandoned form leaves orphan files, which is fine. Each size row picks its photo from a row of thumbnail radios, "Main photo" first. Per-size uploads go away.
- **Store:** the product page shows the main photo with a thumbnail row under it, hidden with one photo. A thumbnail changes only the photo, never the size or price. Choosing a size shows its photo, or the main photo when it has none.
- **Unchanged:** category listings, social previews and JSON-LD use the main photo; the card picker and order line item snapshots use the size's photo. Alt text stays generated from the product name and size. Courses and delivery photos keep the single-photo picker; renaming the course's `image_slug` is TASK-85. File naming stays as is.
- **Not live yet:** regenerate migrations and reseed rather than migrating data.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A product holds 1 to 8 ordered photos and the first is shown wherever a single product photo is shown today
- [x] #2 A size with no photo of its own shows the product's main photo, and follows it when the main photo changes
- [x] #3 The product form can't crash on a size photo whatever sizes are added or removed
<!-- AC:END -->
