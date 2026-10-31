---
id: TASK-161
title: Give each special day its own page in every language
status: needs-triage
assignee: []
created_date: '2026-10-31 20:30'
labels:
  - spec
  - customers
dependencies: []
priority: medium
type: feature
ordinal: 296000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Each of the shop's special days has its own page in Finnish, Swedish and English, showing what to order for it and the last day to order.

**Why:** People search for the occasion, not the shop: "ystävänpäivän kukat Vaasa", "morsdagsblommor Vasa", "Mother's Day flowers Vaasa". Today those searches land on nobody's page, and the store doesn't tell a customer on 6 May that Sunday is Mother's Day or by when they must order.

### What to build

- One page per key date in `Edenflowers.Fulfillment.KeyDates` (Valentine's Day, Women's Day, Mother's Day, Father's Day), at localised URLs such as `/fi/aitienpaiva`, `/sv/morsdag`, `/en/mothers-day`.
- A short, warm introduction in Jennie's voice (a few sentences, not SEO filler), this year's date and the order-by date, then the products she picks for it.
- Which products show is a read action, not a filter in the LiveView. How Jennie picks them is open: a category per occasion, or a tag on products.
- Title, description, OG image and sitemap entries, with `hreflang` alternates between the three languages.
- Out of season the page stays up (so it keeps its ranking) and says when the day falls next year.
- The store and home page point to the next upcoming occasion's page in the weeks before it, and the notice bar can link to it.

### Open questions

- How Jennie chooses the products for each occasion.
- Whether Christmas comes back as an occasion page even though it isn't a delivery key date.
- Route slugs are URL changes; review them as `priv/gettext/README.md` says for route translations.
- Each page's copy is Jennie's, Swedish first.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every key date has a page in sv, fi and en at a localised URL, listed in the sitemap with hreflang alternates
- [ ] #2 Each page shows this year's date, the last day to order and the products chosen for it
- [ ] #3 Out of season a page says when the day falls next
- [ ] #4 The store points to the next occasion's page in the weeks before it
<!-- AC:END -->
