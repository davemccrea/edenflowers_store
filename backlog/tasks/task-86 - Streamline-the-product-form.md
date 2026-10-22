---
id: TASK-86
title: Streamline the product form
status: done
assignee: []
created_date: '2026-10-21 17:33'
updated_date: '2026-10-22 04:38'
labels:
  - spec
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 174000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie edits a product's stock, price and status without scrolling past three descriptions, and photos lead the page.

**Why:** The product form after TASK-84 feels underbaked: photos sit in a narrow sidebar, three stacked languages push sizes below the fold, each size row is about 210px tall with a Draft checkbox, a red Remove button and a thumbnail picker, and there are two Save buttons. Quick edits (stock, price, sold out, publish) are the common task and should be the easy one.

### Decisions (grilled 2026-10-21)

- **Header:** sticky, with title, a Published/Draft switch, View in store and the only Save. The switch is a form field and saves with Save. The bottom "Save product" button goes.
- **Photos:** lead the main column, above sizes. Each tile has always-visible icon buttons (star top-left, filled on the main photo, click to make main; × top-right to remove), so it works on an iPad. No drag and drop. The whole Photos card accepts dropped files; the add tile reads "Add photos · or drop them here"; an uploading photo shows its preview with a progress overlay (as in fluxonui/live-gallery).
- **Sizes:** a compact table, one line per size: thumbnail, size, price, stock, Visible toggle (the size's draft), trash icon. At phone width each row wraps to two lines. "Add size" and "Mark every size sold out" sit in the table footer.
- **Size photo:** the row's thumbnail opens an admin_drawer ("Photo for Medium") with large tiles, main first with a "Main" badge. One click picks and closes; picking the main photo means "follow the main photo" (own_photo_slug nil). With one photo the thumbnail isn't a button. Saved with the product, like every other field.
- **Languages:** tabs (English | Svenska | Suomi), English first. A tab with an empty name or description shows a dot. Translate stays inside each tab.
- **Sidebar:** "In the store": category, position, featured, free delivery, subscription, plus VAT (product-level, moved from under sizes). Product draft moves to the header switch.
- **Unchanged:** both drafts stay (product and size), since hiding a size isn't selling it out. Position stays a number here; reordering on the products list is TASK-87.
- **Process:** a throwaway prototype of the layout comes first, reviewed before any LiveView work.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A size's price and stock can be edited without scrolling on a 1440x900 screen with three sizes
- [x] #2 The form has one Save, reachable at any scroll position
- [x] #3 Every photo action and the size photo choice work by touch
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Prototype verdict (TASK-86.1): layout A as grilled. Build with app components first, then DaisyUI, custom only if required.

2026-10-22 status audit: TASK-86.2, .4, .5 and .6 are done. TASK-86.3 remains ready-for-agent for the whole-card photo drop target. AC #1 still needs a 1440x900 layout check with three sizes after name and description moved above Photos (db603ce1).
<!-- SECTION:NOTES:END -->
