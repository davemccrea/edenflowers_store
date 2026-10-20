---
id: TASK-74
title: 'Describe the shop, products and courses with structured data'
status: ready-for-agent
assignee: []
created_date: '2026-10-20 10:26'
labels:
  - spec
  - customers
dependencies:
  - TASK-69
priority: medium
type: feature
ordinal: 156000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Public pages carry schema.org JSON-LD that states the business, product and course facts already visible on the page, so search engines can show them as richer results.

**Why:** Google can show price and stock under a product link, course dates in event results, and connect the site to Eden Flowers' Business Profile, but only if the facts are stated in a form it reads. None of the pages has any today (docs/reviews/seo-audit.md, finding 3).

### Decisions

- **`Florist`** (a LocalBusiness subtype) on the home and contact pages: name, url, logo, image, address (Myrvägen 1, Vaasa), geo, telephone, email, opening hours, area served (Vaasa, Korsholm), `sameAs` links to Instagram, Facebook and the Business Profile once it exists (TASK-73). Read the hours and contact details from wherever the footer reads them, so the two can't drift.
- **`Product`** on product pages: name, description, image, and an `AggregateOffer` (EUR `lowPrice`/`highPrice` across sizes, `offerCount`) or one `Offer` when there is a single size. Availability `InStock` or `OutOfStock` from the sold-out state.
- **`Event`** on course pages: name, description, image, start and end in Europe/Helsinki, location (the place on the course), `offers` with price, availability from seats left, and `eventStatus`. Courses that have passed keep their page but get no Event markup.
- One small helper renders `<script type="application/ld+json">` from a map, so each page only builds its map. Encode with Jason so text is escaped safely.
- Uses the per-language URLs from TASK-69, which is why it waits for it.

Only mark up what the page visibly shows. Validate with Google's Rich Results Test on staging.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Home and contact pages render valid Florist JSON-LD matching the footer details
- [ ] #2 Product pages render valid Product JSON-LD with EUR prices and availability
- [ ] #3 Upcoming course pages render valid Event JSON-LD; past course pages render none
- [ ] #4 Google's Rich Results Test reports no errors for one page of each type on staging
<!-- AC:END -->
