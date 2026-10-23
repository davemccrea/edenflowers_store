---
id: TASK-78
title: >-
  Write the launch catalogue's product names and descriptions in all three
  languages
status: done
assignee: []
created_date: '2026-10-20 10:26'
updated_date: '2026-10-23 12:15'
labels:
  - spec
  - customers
  - admin
dependencies: []
priority: high
type: chore
ordinal: 160000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Every product in the store at launch has a real name and a helpful description in English, Finnish and Swedish.

**Why:** A product's description is also its search snippet (meta description) and the main text Google indexes for that page. Local and staging data use placeholders ("Bouquet 1", Lorem ipsum) from `priv/repo/seeds.exs`; production seeds only categories, so the products Jennie enters are all search engines will see (docs/reviews/seo-audit.md, finding 2).

A good description says what the bouquet or plant is like (style, colours, typical flowers, seasonal substitutions), the size, care, and delivery or pickup. The first sentence matters most: Google shows roughly the first 150 characters.

Also check the category descriptions seeded in `priv/repo/seeds/production.exs`, which become the store pages' search snippets, still read like Jennie.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every product visible in the production store has a real name and description in en, fi and sv
- [x] #2 No draft or placeholder product is visible in the store or listed in /sitemap.xml
<!-- AC:END -->
