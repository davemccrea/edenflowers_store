---
id: TASK-77
title: Give product pages a single h1
status: ready-for-agent
assignee: []
created_date: '2026-10-20 10:26'
labels:
  - spec
  - customers
  - quick
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
- [ ] #1 Product pages contain exactly one h1 at every breakpoint and look unchanged
<!-- AC:END -->
