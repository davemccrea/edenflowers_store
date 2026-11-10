---
id: TASK-187
title: Let customers choose a bow colour on a wreath
status: done
assignee: []
created_date: '2026-11-10 11:05'
updated_date: '2026-11-10 13:03'
labels:
  - spec
  - customers
  - admin
dependencies: []
type: feature
ordinal: 353000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Customers should be able to pick the colour of the bow on a product that offers one, e.g. a Christmas wreath with a red, yellow or blue bow. Today a product has sizes but no other choice; the bow is chosen by Joe Shopper with no way to say which.

Decisions (grilled 2026-11-10):

- **Shape:** one concrete choice, not an options system. A fixed colour list in code (`Edenflowers.Catalog.BowColour`: red, yellow, blue), with gettext labels "Red bow" / "Yellow bow" / "Blue bow". A new colour is a one-line code change; the store only ever shows the colours a product offers.
- **Product:** `bow_colours` (array of colours), ticked in the admin product form. Empty means the product asks nothing.
- **Line:** `bow_colour` on `line_items`, carried by the line from the product page. It changes no price and takes no stock: a batch of 20 wreaths shares one stock count.
- **Chosen on the product page only**, as plain-text radios under the size picker (house `size-option` style), legend "Bow colour", the first colour preselected so it is always sent. Changing the colour means removing the line and adding it again, like changing size.
- **Two colours are two cart lines**; the same colour added twice merges into one line with a higher quantity. That needs `bow_colour` in `unique_product_variant` with `nils_distinct?: false`, otherwise every colourless product's lines stop merging.
- **Validation:** `add_to_cart` refuses a missing colour when the product offers one, and a colour the product doesn't offer.
- **Admin:** a colour select in the Custom Order catalogue line picker, blank allowed ("Jennie decides"), so a phone order can carry a bow too. Her catalogue lines must not fail the web's required-colour rule.
- **Shown as "Red bow"** beside the size in the cart drawer and checkout, the confirmation and updated emails and their line totals, the pay page, the account order list, the receipt PDF, the admin order detail, the prep board, and the order log's entered-items summary. Compact summaries that never showed the size now show it as well, so two colours of one wreath can't read as identical rows.
- **Translations:** Swedish and Finnish written in this change; `mix gettext.update`, `mix gettext.check`, `mix gettext.stats`.
- **Rollout:** no data backfill. Jennie ticks red/yellow/blue on the wreath products in the product form after deploy.

Not doing: per-colour stock or price, colours on add-ons, changing colour from the cart, a generic multi-option system, subscription colour handling.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A product can offer no colours or a set of them; the product form ticks which.
- [x] #2 The product page shows a Bow colour radio group under the size picker only when the product offers colours, with the first preselected.
- [x] #3 Adding to the cart records the chosen colour on the line and refuses a missing or unoffered colour.
- [x] #4 Two colours of the same size are two cart lines; the same colour added twice merges into one line with quantity two.
- [x] #5 The colour reads "Red bow" beside the size in the cart, emails, pay page, account order list, receipt PDF, admin order detail, prep board and order log.
- [x] #6 Admin Custom Order lines can set a colour, and may leave it blank.
- [x] #7 Colour names are translated into Swedish and Finnish and pass mix gettext.check.
- [x] #8 Colourless products, existing lines and existing orders are unaffected.
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Implemented: `Edenflowers.Catalog.BowColour` (red, yellow, blue) with gettext labels, `products.bow_colours` (ticked as chips in the product form), and `line_items.bow_colour`.

The product page shows a Bow colour radio group under the size picker, starting on the cart's colour or the first offered, and always sends a choice.

`add_to_cart` requires a colour the product offers (`Validations.BowColour`), while the admin's `enter` may leave it blank.

`unique_product_variant` now covers the colour with `nils_distinct?: false` and a partial index (`product_variant_id IS NOT NULL`), so colours are separate lines, the same colour merges, and Custom Order items are untouched. Stock stays per size: every colour counts against the same stock, both when adding to the cart and when pressing + on a line.

Only a wreath category (`product_type: :wreath`, read as `ProductCategory.offers_bows`) offers bows; a product moved out of one loses its colours. A wreath is never subscribable (`Catalog.Changes.FitWreathChoices`; the admin form hides the box): a Subscription doesn't keep the colour, so its later deliveries would be refused.

The colour reads as "Red bow" beside the size in the cart, pay page, account list, emails, receipt PDF, admin order detail, prep board, order log and Custom Order line label. `Format.line_item_choices/1` is the one place that composes it. The order log now names a line's size too ("2 × Spring Bouquet · Medium").

Swedish and Finnish written for the colour labels, "Bow colour" and the validation messages; `mix gettext.check` passes.

Tests: line item rules (choice, refusal, merging, shared stock on add and +, admin blank), product page radios and adding a second colour, a wreath never subscribable, admin Custom Order colour and blank, receipt payload label, colourless products unchanged.

Verification: `mix test` 2213 tests, 0 failures, 1 skipped; `mix ash.codegen --check`, `mix format --check-formatted`, `mix gettext.check` pass; `mix credo --strict` only the pre-existing seeds_test issue. Receipt and invoice samples render with Typst, and a bow receipt was checked visually.

Not verified in a browser: the product page and admin screens were covered by LiveView tests, no manual visual pass.
<!-- SECTION:FINAL_SUMMARY:END -->
