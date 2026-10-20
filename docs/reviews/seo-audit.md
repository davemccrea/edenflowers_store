# SEO audit — 20 October 2026

## Scope and assessment

Prelaunch audit of the running application at `http://localhost:4000` and the current working tree, including existing uncommitted changes. Production maintenance behavior is excluded: this store has not launched.

Fetched every URL in the local XML sitemap (20 pages), inspected initial server-rendered HTML, checked language negotiation, and requested invalid product, category, and course URLs. Reviewed routing, layouts, images, metadata, and application JavaScript source. No application code was changed.

The local foundations are sound: all 20 sitemap pages return 200, have descriptions and self-referencing canonicals, and expose their principal content in server-rendered HTML. The largest remaining architectural issue is language discovery. Structured data and service-specific titles are the next improvements.

No browser-rendered DOM audit, production performance measurement, Search Console analysis, backlink analysis, or Google Business Profile review was performed. This is not a ranking or traffic assessment. Local HTTP URLs are expected and are not defects.

## Prioritized findings

### 1. High — translated pages have no distinct URLs

**Evidence:** Requests to `/` with `Accept-Language: fi`, `sv-FI`, and `en-GB` return Finnish, Swedish, and English respectively, while all canonicalize to the same `/` URL. `lib/edenflowers_web/router.ex:17` selects language from session/browser headers and defaults to English. The language picker changes the session through `/locale/:locale`; neither the layout nor sitemap supplies hreflang.

**Impact:** Finnish and Swedish content may not be discovered reliably. Googlebot usually sends no Accept-Language header, so the default English version is especially likely to be crawled.

**Fix:** Give each language a stable URL, such as `/fi/`, `/sv/`, and `/en/`, with matching localized paths for services and products. Render the requested URL's language independently of session preferences. Add ordinary language-switch links, self-canonicals, reciprocal hreflang, and localized sitemap entries. Decide how existing unprefixed URLs redirect before launch.

See [Google's multilingual-site guidance](https://developers.google.com/search/docs/specialty/international/managing-multi-regional-sites).

### 2. High if launch data — five products contain placeholder content

**Evidence:** The local sitemap includes “Bouquet 1”, “Bouquet 2”, “Bouquet 3”, “Plant”, and “Pre-Loved Item”. All five use the same Lorem ipsum text as their visible description and meta description. Product pages take metadata directly from the product record in `lib/edenflowers_web/features/store/product_live.ex:63`.

**Impact:** If published, these pages provide little useful information to shoppers or search engines.

**Fix:** Confirm that these are development fixtures. Before launch, replace any equivalent production records with real product names and helpful descriptions: style, contents or seasonal substitutions, sizing, care, and delivery/pickup details. Translate the actual catalog content. Keep unfinished products out of the public catalog and sitemap.

This is a launch data check, not evidence that production contains these records.

### 3. Medium — no structured-data implementation found

**Evidence:** None of the 20 initial HTML responses contains JSON-LD. Searches of `lib`, `assets`, and configuration found no `schema.org`, JSON-LD, or microdata implementation. This supports a source-level implementation gap; absence in a fully rendered browser DOM was not verified.

**Impact:** The application is missing an opportunity to describe product offers and business details explicitly for supported search appearances. Structured data does not guarantee rich results or improved rankings.

**Fix:** Add Product/Offer data using real EUR prices, availability, images, and canonical URLs. Add an appropriate LocalBusiness/Florist entity with the actual business name, address, phone, opening hours, and official profiles. Consider Event markup for eligible dated workshops. Keep every claim consistent with visible content; validate rendered pages with Google's Rich Results Test.

References: [Product structured data](https://developers.google.com/search/docs/appearance/structured-data/product), [LocalBusiness structured data](https://developers.google.com/search/docs/appearance/structured-data/local-business).

### 4. Medium — important service titles are too generic

**Evidence:** Rendered titles are `Eden Flowers | Weddings`, `Eden Flowers | Condolences`, and `Eden Flowers | Courses`. Their H1s are equally broad. The descriptions already explain the services and Vaasa location well.

**Impact:** Titles give searchers less information about the service and location than the page content supports.

**Fix:** Use descriptive, naturally localized titles, for example:

| Page | Suggested English title |
| --- | --- |
| `/weddings` | Wedding Flowers in Vaasa & Korsholm \| Eden Flowers |
| `/condolences` | Funeral Flowers in Vaasa & Korsholm \| Eden Flowers |
| `/courses` | Floristry Workshops in Vaasa \| Eden Flowers |
| `/store/bouquets` | Flower Bouquets in Vaasa \| Eden Flowers |

Use corresponding descriptive H1s. Update the title component's fixed brand prefix if adopting brand-last titles. Translate for Finnish and Swedish search intent rather than copying English phrasing literally. These examples are editorial recommendations, not search-volume-validated keyword targets.

### 5. Medium — invalid category/course URLs redirect to generic listings

**Evidence:** `/store/nonexistent-seo-audit` returns 302 to `/store/bouquets`; `/courses/nonexistent-seo-audit` returns 302 to `/courses`. Both destinations return 200. Invalid product IDs correctly return 404. Relevant branches: `store_live.ex:36–40` and `course_live.ex:32–36`.

**Impact:** Redirecting nonexistent resources to generic listings obscures missing-page semantics and can be interpreted as soft 404 behavior.

**Fix:** Return a real 404 for unknown category/course IDs, with useful navigation in the error page. Redirect only when there is a genuine equivalent replacement. Preserve useful expired workshop pages where appropriate.

### 6. Low — product templates duplicate the H1

**Evidence:** Every product response has two identical H1 elements, in mobile and desktop headers (`product_live.ex:101` and `:131`).

**Impact:** This is a semantic cleanup opportunity, not a critical ranking defect. CSS hides one header at each breakpoint.

**Fix:** Prefer one responsive heading element when changing the product layout.

### 7. Low / measure first — Stripe loads on all pages

**Evidence:** `components/layouts/root.html.heex:44` loads Stripe.js globally, including marketing pages.

**Impact:** It adds third-party work, but no actual Core Web Vitals regression was measured.

**Fix:** Profile a production build on mobile before changing this. Consider loading Stripe only where required, while preserving payment initialization and relevant Stripe guidance.

## What is already working

- All 20 sitemap URLs return 200 and matching self-canonicals.
- All 20 have nonempty descriptions. Five product descriptions need the fixture check above.
- Initial HTML includes headings, product details, and crawlable navigation links.
- The homepage title and H1 clearly identify the florist and Vaasa.
- Service pages include real work, descriptive copy, and contact paths; wedding content includes pricing and process information.
- The layout includes address, opening hours, business ID, and contact navigation.
- Images have dimension attributes; the image component supports WebP, responsive sources, lazy loading, and priority loading for hero/product images.
- Invalid product URLs return 404.
- The local robots file advertises the intended production sitemap and excludes transactional areas.

Robots exclusions control crawling, not guaranteed removal from search. Where exclusion from indexing matters, use appropriate authentication or crawlable noindex responses; do not assume a blocked URL cannot appear in results. See [Google's robots.txt guidance](https://developers.google.com/search/docs/crawling-indexing/robots/intro).

## Action order and launch acceptance

1. Decide and implement the public language URL structure before launch.
2. Confirm the launch catalog contains no placeholder names/descriptions and all intended languages are complete.
3. Add and validate product/business structured data.
4. Improve service titles and missing-resource responses.
5. On the deployed launch candidate, verify HTTPS/host redirects, production canonicals, reciprocal language annotations, sitemap responses, and indexability. Recheck that maintenance mode is off at launch.
6. Measure mobile performance on a production build; localhost development timings cannot establish production Core Web Vitals.
7. After launch, submit the sitemap in Search Console and use indexing/query data to prioritize further work. Review Google Business Profile details, opening hours, categories, photos, reviews, and consistency with the site.

The production maintenance redirect and unavailable production sitemap observed earlier are deliberately excluded from this prelaunch assessment.
