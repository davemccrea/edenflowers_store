---
id: TASK-169.1
title: Give products readable slugs
status: done
assignee: []
created_date: '2026-11-01 21:15'
updated_date: '2026-11-01 21:31'
labels: []
dependencies: []
parent_task_id: TASK-169
type: feature
ordinal: 315000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Product links Jennie shares should read like the product, not a UUID.

Follow the decisions in TASK-169. Introduces the shared slugify function. Slug attribute is nullable here (TASK-169.3 makes it required); `Release.migrate` backfills missing ones.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A product is reachable at /:language/product/:slug
- [x] #2 UUID product URLs and earlier slugs permanently redirect to the current slug URL
- [x] #3 Earlier slugs are reserved; a clashing generated slug gets -2, -3, …
- [x] #4 The product form has a Link field with URL preview that fills from the name on new products and normalises what Jennie types
- [x] #5 Renaming a product leaves its slug unchanged
- [x] #6 Every product URL the app builds (share drawer, emails, sitemap, admin links) uses the slug
- [x] #7 Release.migrate backfills slugs for existing products
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Redirects are a router plug (Plugs.RedirectOldProductLinks), since a LiveView can only redirect with 302. Core inputs debounce on blur, so the new-product Link fills when Jennie leaves the Name field. No email builds a product URL. Release.migrate backfill verified against the worktree DB through mix run --no-start (the eval path bin/migrate uses).
<!-- SECTION:NOTES:END -->
