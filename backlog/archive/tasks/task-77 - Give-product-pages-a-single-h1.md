---
id: TASK-77
title: Give product pages a single h1
status: done
assignee: []
created_date: '2026-10-20 10:26'
updated_date: '2026-10-20 12:34'
labels:
  - spec
  - customers
dependencies: []
priority: low
type: refactor
ordinal: 159000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The product page renders its name in one `<h1>` that works at every breakpoint.

**Why:** The page has two identical `<h1>` elements, one in the mobile header and one in the desktop header, with CSS hiding one at each size (product_live.ex, the two `page-title` headings). Crawlers that read the HTML see the heading twice (docs/reviews/seo-audit.md, finding 6). Hidden copies aren't read by screen readers, so this is a tidy-up, not an accessibility bug.

Keep the layout as it looks today; the `product-name` test id stays on the remaining heading.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Product pages contain exactly one h1 at every breakpoint and look unchanged
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Removed the mobile-only header. The remaining header sits in the product grid: above the image on mobile, top of the right column on desktop (md:col-start-2 md:row-start-1), with the image spanning both rows and md:grid-rows-[auto_1fr] so a tall image doesn't push the details down. md:gap-y-8 keeps the old header-to-description spacing. Checked at 1280px and 390px: one h1, layout unchanged. Desktop reading order now puts the heading before the image.
<!-- SECTION:NOTES:END -->
