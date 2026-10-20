---
id: TASK-70
title: Ask Google and Bing to crawl the shop once it goes live
status: ready-for-human
assignee: []
created_date: '2026-10-20 10:12'
updated_date: '2026-10-20 10:26'
labels:
  - spec
  - customers
  - quick
dependencies: []
priority: high
type: chore
ordinal: 152000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Once production leaves maintenance mode, register the site with Google Search Console and Bing Webmaster Tools and ask both to crawl it.

**Why:** Google may have seen edenflowers.fi while every page redirected to /back-soon. Left alone it can take weeks to recrawl and notice the real shop; submitting the sitemap and requesting indexing gets it done in days.

### Steps

1. Confirm maintenance mode is off: `curl -sI https://edenflowers.fi/` returns 200, not a redirect to /back-soon.
2. In Google Search Console, add a **Domain** property for `edenflowers.fi` and verify it with the DNS TXT record in Cloudflare.
3. Sitemaps: submit `https://edenflowers.fi/sitemap.xml`.
4. URL Inspection: request indexing for `/`, `/store/bouquets`, `/weddings`, `/condolences`, `/courses`, `/about` and `/contact`.
5. In Bing Webmaster Tools, import the site from Search Console (this also covers DuckDuckGo and Ecosia).
6. A week later, check the Search Console Pages report for errors and that /back-soon has dropped out.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The Search Console property is verified and the sitemap reads Success
- [ ] #2 Indexing was requested for the key pages
- [ ] #3 Bing Webmaster Tools has the site and sitemap
- [ ] #4 Before requesting crawls, on production: http redirects to https, canonicals and hreflang point at production URLs, /sitemap.xml returns 200, and public pages carry no noindex
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-20 10:26

---

From docs/reviews/seo-audit.md: verify the deployed site before asking Google to crawl it.

---
<!-- COMMENTS:END -->
