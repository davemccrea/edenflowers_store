# Eden Flowers: AI SEO audit rerun

Audited: **2026-10-28, approximately 10:52–10:56 UTC**. Target: https://edenflowers.fi. Repository: `d7ee7f76`.

Baseline: [earlier audit](ai-seo-audit.md), also dated 2026-10-28. This is a later same-day recheck, not evidence of a longer-term visibility trend. The original report is preserved.

## Executive summary

**The maintenance blocker is gone.** All **57/57 sitemap URLs** return HTTP 200 anonymously, with substantive server-rendered content. The eight tested crawler/retrieval user-agent strings also receive the homepage successfully.

The priority has moved from opening the site to factual consistency, public-product visibility and measuring actual local recommendations. Wedding metadata still promises unpublished prices. The home delivery-radius concern is a future drift risk, not a demonstrated live price discrepancy. Product descriptions, size information and subscription discovery are stronger than could be verified during the first audit.

**Actual AI citations, mentions and recommendations remain unmeasured.** HTTP access and good markup do not establish that an engine has indexed, cited or recommended Eden Flowers.

No application code, customer copy, translations, production settings or database records were changed. No checkout, enquiry or newsletter form was submitted.

## 1. Changes since the baseline

| Earlier finding | Rerun result | Disposition |
|---|---|---|
| Public pages redirect to maintenance | All 57 sitemap destinations return 200; `/back-soon` now redirects to `/` | **Resolved in live observations** |
| Crawler-string requests redirect to maintenance | All eight tested strings receive `/en` with 200 and substantive HTML | **Resolved from this connection**, not verified vendor IPs |
| Live product copy could not be assessed | Four products × three languages are readable; seasonal variation, prices and selected-size measurements are present | Narrow the earlier content recommendation |
| Wedding metadata promises hidden prices | Still present in English, Finnish and Swedish; no public price list | **Open, confirmed live** |
| Home metadata hardcodes free-delivery distance | Still hardcoded at 5 km; live home, FAQ and eligible product currently agree on 5 km | **Open drift risk**, not current factual mismatch |
| Drafts are not filtered in product-page read | Repository behavior remains unchanged | **Open policy decision**; no live draft exposure demonstrated |
| Subscription FAQ requires interaction on product page | Still absent initially, but the home already explains frequency and change deadline, and the FAQ explains billing/cancellation | **Partial gap**, not site-wide missing information |
| AggregateOffer and global x-default | Both still present | Secondary refinements |
| Missing `/llms.txt` | Still 404 | Optional experiment, not a blocker |
| External AI visibility/local profiles unknown | Still no search-platform or account evidence | **Unmeasured**, not failed |

## 2. Access and discovery: live evidence

### Coverage and checks

The live sitemap contains **19 page destinations per language**, 57 total:

- Nine marketing/help/legal pages per language.
- Three category pages per language.
- Four products per language.
- Three dated course pages per language.

| Check | Result |
|---|---|
| Sitemap fetch and XML parsing | Pass, HTTP 200 |
| All sitemap destinations | **57/57 HTTP 200**, no redirects |
| Self-referencing canonical matching requested URL | **57/57** |
| Nonempty title and meta description | **57/57** |
| Exactly one H1 element | **57/57** |
| HTML language | 19 `en-GB`, 19 `fi`, 19 `sv-FI` |
| Localized alternate URLs | Targets exist in the sitemap and link back to the source page |
| `noindex` in robots meta or X-Robots-Tag | None detected on the 57 pages |
| Image elements with an alt attribute | No missing attributes detected; this does not assess alt quality |
| Embedded JSON-LD | 33 blocks parse as JSON: 9 Florist, 3 FAQPage, 12 Product, 9 Event |
| Root `/` | HTTP 302 to `/sv` on this request |
| `/back-soon` | HTTP 302 to `/` |
| `/llms.txt` | HTTP 404 |

The crawler-string test covered `OAI-SearchBot`, `PerplexityBot`, `Claude-SearchBot`, `ChatGPT-User`, `Claude-User`, `Perplexity-User`, `Googlebot` and `Bingbot` on `/en`. All eight returned HTTP 200 with the same response-body byte count as the browser-string request. These are synthetic user-agent tests from the audit connection, not requests originating from verified crawler networks.

### Edge policy remains separate

The live `robots.txt` still includes Cloudflare-managed directives before the repository rules:

- `Content-Signal: search=yes,ai-train=no,use=reference`.
- Named blocks including GPTBot, ClaudeBot and Google-Extended.
- No explicit block for the tested search-discovery or user-retrieval tokens.
- The file defines `ai-input` but does not set it. Its definition of `search` explicitly excludes AI-generated summaries; do not describe `search=yes` as an explicit summary permission.

Preserve deliberate training restrictions. OpenAI's current documentation explicitly separates OAI-SearchBot search inclusion from GPTBot training controls. Do not unblock training crawlers to chase citations. Review actual Cloudflare verified-bot logs and challenges before claiming genuine vendor access is confirmed.

## 3. Confirmed strengths and narrower content gaps

### Product pages: much of the requested information already exists

The live catalogue has Stillness, Colour Burst, Watercolour and Bouquet of the Week, localized in all three languages. All four show small/medium/large prices of **€35/€45/€70** and initially select the €45 medium size. The delivered HTML includes **40–50 cm · 15–20 stems** for that selected size. Descriptions explain the colour/style, likely occasions and seasonal or weekly variation; photographs are explicitly examples.

Bouquet of the Week additionally shows the **5 km free-delivery eligibility** and buy-once/subscription choice in the initial response. Finnish and Swedish versions also expose those essentials.

Do not add generic paragraphs about dimensions or substitutions as though those facts were missing. The remaining useful product-page gaps are a concise explanation of delivery/pickup/date selection and, on the subscribable product, subscription frequency, payment timing and change deadline **before** toggling the option. Reuse authoritative policy data rather than copying policy strings into product descriptions.

### Subscription discovery already works at site level

The home contains an initial-HTML “Flower subscription” section with weekly/two-weekly/four-weekly frequency and the three-day change deadline. The public FAQ includes first-payment timing, subsequent charging two days before fulfillment, and pause/change/cancellation information. A dedicated subscription page is not an immediate prerequisite.

### Local identity, service proof and FAQs are readable

Home, about and contact pages contain Florist JSON-LD. Visible text establishes Jennie's identity, Minimossen, the shop address and hours. Home and about pages include attributed customer feedback as text; the wedding gallery credits photographers. The FAQ covers delivery radius, charging, pickup, care, payment, wedding lead time and travel.

The early home summary could still connect Eden Flowers, Jennie, Vaasa/Vasa and Minimossen more directly, but the entity is not absent from the delivered page. Keep this a modest editorial improvement, not a redesign requirement.

### Courses are an additional near-term opportunity

Three future course pages are public in all languages: Christmas Door Wreath on **19 and 24 November 2026**, and Christmas Arrangement on **16 December 2026**. Event JSON-LD exposes dates with Finnish winter-time offsets, venue and **€42** price. The sampled 19 November page visibly agrees on time, venue and price, and states the teaching language is Swedish even on the English page.

Include local floristry-course prompts in the visibility baseline while these events are bookable. Their language of instruction must remain clear; translated booking pages do not imply multilingual teaching.

## 4. Prioritized remaining work

### P1 — Correct the wedding metadata promise

Live `/en/weddings`, `/fi/haat` and `/sv/brollop` descriptions promise “Prices and past weddings” or its translation, while the public page has a quote process rather than the withdrawn price list. `lib/edenflowers_web/features/marketing/weddings_live.ex` still sets `@show_prices? false`.

**Recommendation:** align metadata with the visible service and enquiry process, preserving Jennie's decision not to publish prices. Follow `priv/gettext/README.md` before changing copy and translations.

### P1 — Decide public draft/preview visibility

`lib/edenflowers/catalog/product.ex` still documents that `:for_product_page` does not filter drafts; `ProductLive` uses the corresponding product lookup. Sitemap exclusion is not access control or an indexing policy.

**Recommendation:** confirm intended preview behavior. If drafts should be private, enforce it in the Ash read action and provide an authorized preview separately. Do not guess unpublished IDs to test production. This remains a repository-level exposure risk, not a claim that any current public product is a draft.

### P2 — Remove delivery-policy drift risk

`lib/edenflowers_web/features/marketing/home_live.ex` still hardcodes 5 km in metadata while visible delivery text reads fulfillment configuration. Current live values agree: the home and FAQ show the 5 km eligible-product exemption and a standard charge of €3 plus €0.80/km; the FAQ states a 20 km driving-distance delivery area.

**Recommendation:** derive metadata and visible policy from the same configuration, including the no-free-radius case. Preserve product eligibility and driving-distance semantics. Do not present all bouquets or every address as eligible for free delivery.

The home currently shows the next available day as **Saturday 31 October**, while the FAQ describes the *usual* same-day cutoff and says checkout determines available dates. This is not proof of a conflict, but assistants must not infer a same-day delivery guarantee from the generic cutoff.

### P2 — Bring existing decision facts onto service/product pages

- Wedding page: surface the FAQ's typical **9–12 month booking lead time** and separately quoted travel outside Vaasa near the service/enquiry explanation.
- Subscribable product: expose the essential terms before interaction, without removing the current choice controls.
- Funeral page: local church/chapel coverage and ordering details are already useful. Confirm lead time and pricing approach with Jennie before adding them; do not invent minimum prices or turnaround promises.

### P2 — Refine structured data and fallback links

All four products use an AggregateOffer with the accurate €35–€70 range and three offers, but no size-to-price mapping within JSON-LD. Consider per-variant Product/Offer data and stable florist/seller identifiers. Meet Google's variant URL/identifier requirements if implementing ProductGroup; do not manufacture GTINs, ratings or variant URLs that do not actually preselect a size.

All pages still point `x-default` to `/`, including products and events. Review whether to omit it on detail pages or provide a corresponding default destination. The reciprocal localized alternates and self-canonicals already work; this is not a critical access failure.

Course Event offers lack a booking `url`. Review that and venue/address completeness against current Event guidance during structured-data validation. JSON parsing in this rerun is **not** a Google Rich Results Test or proof of rich-result eligibility. None of these changes guarantees AI citations.

### P3 — Optional discovery files

Keep `/llms.txt`, Markdown mirrors, llms-full, OKF and agent-action protocols below the factual and measurement work. There is no demonstrated retrieval problem requiring them. Google explicitly says special AI text files or schema are not required for AI Overviews/AI Mode. Do not duplicate a changing flower catalogue into an unmaintained price file.

## 5. Next measurement run

Use the **12-prompt Swedish/Finnish/English portfolio in the original report**, maintaining each language/Finland/engine configuration separately. Add native-reviewed course prompts, for example:

- Swedish: `Finns det kurser i att binda julkransar i Vasa?`
- Finnish: `Missä Vaasassa voi osallistua joulukranssikurssille?`
- English: `Are there Christmas wreath workshops in Vaasa, and what language are they taught in?`

These are hypotheses, not measured demand. Run each prompt 3–5 times per platform in fresh sessions on ChatGPT Search, Perplexity and the available Google AI surfaces. Record exact prompt, date, language/market, engine, whether an AI answer appeared, **mention/citation/recommendation separately**, cited URLs, competing florists and factual errors. Report rates with denominators; an absent AI answer is not equivalent to an answer omitting the brand.

Now that access works, the highest-value external checks are:

1. Search Console/Bing index and canonical inspection of home, services, one product and one course; submit the sitemap if needed.
2. Google Business Profile consistency: shop address, map pin, hours, category, services and genuine reviews.
3. Third-party sources actually cited for local florist/course prompts; choose outreach from that evidence rather than generic directory lists.
4. Merchant Center/feed status and local delivery/pickup eligibility if commercially relevant. Account/feed existence remains unknown.

No browser/search-platform integration, Search Console, analytics, Business Profile or Merchant Center account access was available here. No actual assistant answer tests were run. Do not report citation gains, ranking changes, competitor share or sales uplift from this crawl.

## Evidence and sources

Local raw evidence is under `tmp/ai-seo-rerun-2026-10-28/` (ignored, not committed): `requests.json` records initial HTTP tests; `pages.json` records all 57 pages; individual HTML/header/text files preserve responses. `crawl_pages.py` reproduces sitemap-page checks using Python's standard library. Extracted text includes navigation and CSS-hidden content; it is evidence of initial-HTML availability, not a visual/accessibility or interactive checkout test.

Official documentation fetched during the rerun:

- [Google: AI features and your website](https://developers.google.com/search/docs/appearance/ai-features) — no additional AI eligibility requirements or special AI files.
- [OpenAI: bots](https://developers.openai.com/api/docs/bots) — separate search, training and user-triggered retrieval controls.
- [Google: product variants](https://developers.google.com/search/docs/appearance/structured-data/product-variants) — variant markup, identifiers and direct-selection URL requirements.
- [Google: Event](https://developers.google.com/search/docs/appearance/structured-data/event) — event and ticket-offer properties.

The attempted Anthropic crawler-support documentation fetch returned HTTP 403; its current wording was not independently verified in this run. No vendor readiness score or citation-lift statistic is claimed.
