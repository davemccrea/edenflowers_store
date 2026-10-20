---
id: TASK-75
title: Name the service and place in page titles
status: ready-for-human
assignee: []
created_date: '2026-10-20 10:26'
updated_date: '2026-10-20 17:12'
labels:
  - spec
  - customers
  - quick
dependencies: []
priority: medium
type: feature
ordinal: 157000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Page titles say what the page offers and where, with the brand last: "Wedding Flowers in Vaasa | Eden Flowers".

**Why:** The title is the blue link in search results. "Eden Flowers | Weddings" tells a searcher less than the page offers, and putting the brand first spends the part that is never truncated on the shop's name (docs/reviews/seo-audit.md, finding 4).

### Decisions

- Move the brand to a suffix: `live_title` gets `suffix=" | Eden Flowers"` instead of the prefix, and `og:title` matches.
- English titles:
  - Home: Florist in Vaasa
  - Weddings: Wedding Flowers in Vaasa
  - Condolences: Funeral Flowers in Vaasa
  - Courses: Floristry Courses in Vaasa
  - Store category: "<Category> in Vaasa", e.g. Bouquets in Vaasa
  - Products, course pages, About, Contact, FAQ, checkout and admin keep their current titles.
- Write the Finnish and Swedish titles as local searchers would phrase them (e.g. "Hääkukat Vaasa", "Bröllopsblommor i Vasa"), not word-for-word translations. Have Jennie read them.
- Visible H1s stay as they are; they are part of the page design, and the title and description already carry the place.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Titles end in " | Eden Flowers" on every page, including og:title
- [x] #2 Home, Weddings, Condolences, Courses and store category pages use the titles above in en, fi and sv
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Brand moved to a live_title suffix and og:title. Category titles use ~t"%{category} in Vaasa". fi titles are search-phrased without inflection (Hääkukat Vaasa, Hautajaiskukat Vaasa, Floristiikkakurssit Vaasa, %{category} Vaasa); sv: Bröllopsblommor/Begravningsblommor i Vasa, Blomsterkurser i Vasa, %{category} i Vasa. Home keeps its existing Kukkakauppa Vaasassa / Blomsterhandel i Vasa.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-20 17:09

---

Built. Left: Jennie reads the Finnish and Swedish titles.

---

author: @claude
created: 2026-10-20 17:12

---

Dropped Korsholm from the Weddings and Condolences titles; they name Vaasa only. The page descriptions still mention Korsholm.

---
<!-- COMMENTS:END -->
