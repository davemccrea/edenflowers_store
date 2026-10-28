# Eden Flowers: AI visibility, crawler access and content audit

Audited: 2026-10-28. Scope: repository inspection and unauthenticated HTTP requests to https://edenflowers.fi. No production settings, application code or customer copy changed.

## Executive summary

The immediate constraint is availability, not missing AI-specific files. Public pages currently redirect to a maintenance page. Once the storefront is intentionally opened, the existing server-rendered content, localized routes, FAQs and structured data provide a useful foundation.

Actual AI citation and recommendation rates are **not measured** here. No authenticated search-engine, Search Console, Business Profile, Merchant Center or analytics access was available. Requests using crawler user-agent strings test HTTP behavior from this audit's connection, not access from the vendors' verified IP addresses.

## 1. Live crawler access

### Observations

| Request | Result |
|---|---|
| `/en`, `/fi`, `/sv` | HTTP 302 to `/back-soon` |
| `/en/faq` | HTTP 302 to `/back-soon` |
| One public product URL listed in the live sitemap | HTTP 302 to `/back-soon` |
| `/en` with OAI-SearchBot, PerplexityBot, Claude-SearchBot, ChatGPT-User and Googlebot user-agent strings | HTTP 302 to `/back-soon` in every test |
| `/back-soon` | HTTP 200 |
| `/robots.txt` | Accessible; contains Cloudflare-managed additions followed by repository rules |
| `/sitemap.xml` | Accessible XML containing localized marketing, category, product and course URLs |
| `/llms.txt` | HTTP 404 |

Raw responses are stored locally under `tmp/ai-seo/` and `tmp/ai-seo-*` (not part of this report's tracked evidence).

### Priority: public availability

`lib/edenflowers_web/plugs/maintenance.ex` redirects non-admin public visitors while maintenance mode is enabled. `config/runtime.exs` reads `MAINTENANCE_MODE`. The maintenance page has contact details in Swedish and Finnish, but not the public catalogue, service content or florist structured data.

This may be intentional pre-launch behavior. Do not disable it just for crawlers or expose unfinished pages. When ready to open, verify anonymous access first; signed-in admin browsing bypasses this restriction and is not an adequate launch check.

For future short maintenance windows on an already indexed site, consider returning HTTP 503 with an appropriate Retry-After rather than redirecting every public URL to one HTTP-200 placeholder. Do not treat prolonged pre-launch closure as a short outage.

The sitemap currently advertises public URLs whose sampled destinations redirect to maintenance. Recheck its destinations at opening.

### Cloudflare policy: inspect separately from application robots.txt

`priv/static/robots.txt` does not disallow public localized marketing or catalogue pages. Its private-route exclusions are appropriate crawl controls, but are not authentication or privacy protection.

The live response adds Cloudflare rules, including:

- `Content-Signal: search=yes,ai-train=no,use=reference`.
- Disallows for GPTBot, ClaudeBot, Google-Extended and several other named agents.
- No explicit disallow for the tested OAI-SearchBot, PerplexityBot or Claude-SearchBot tokens.

The live file defines `ai-input`, but does not set that signal. Do not interpret `search=yes` as an explicit grant for AI summaries: the response's own definition excludes them. Content signals are not the same as robots crawl controls, and vendor support must be checked separately.

Preserve training opt-outs if intentional. Do not unblock training crawlers as a supposed prerequisite for citations. Review Cloudflare's bot controls, challenges and verified-bot request logs for the actual discovery/retrieval agents after opening; changing Git alone will not remove managed edge rules.

## 2. Existing technical strengths

- Phoenix LiveView templates contain substantive server-rendered page content; no client-only content shell is apparent in the inspected public templates. Confirm the delivered HTML after maintenance ends.
- `lib/edenflowers_web/components/layouts/root.html.heex` supplies canonical URLs, descriptions and alternate-language links when assigned.
- `lib/edenflowers_web/business.ex` centralizes visible business facts and Florist JSON-LD: address, telephone, coordinates, hours, service areas and social profiles.
- Product pages include names, descriptions, imagery, EUR prices and Product offers/availability structured data.
- `lib/edenflowers_web/features/marketing/faq_live.ex` generates visible answers and FAQPage JSON-LD from shared data. Answers include delivery pricing, pickup, payment, cancellation and care.
- FAQ accordions use native `details`/`summary`; their text is not fetched only after a click.
- About and service pages provide Jennie's identity, first-hand work, portfolio photographs, attribution and customer quotations as text.
- Sitemap generation includes all three language versions of the listed pages.

Structured data supports interpretation and search eligibility; it does not guarantee AI citations. FAQ markup should not be presented as a promise of Google FAQ rich results for this florist.

## 3. Product and content improvements, in priority order

### P1: resolve factual inconsistencies

1. **Wedding description promises hidden prices.** `lib/edenflowers_web/features/marketing/weddings_live.ex` sets `@show_prices? false`, while its meta description promises “Prices and past weddings.” Respect Jennie's decision not to publish the price list: align the description with what visitors can actually see rather than restoring hidden pricing for SEO.
2. **Home description hardcodes a delivery distance.** `lib/edenflowers_web/features/marketing/home_live.ex` mentions free delivery within 5 km in metadata, while the visible delivery explanation uses fulfillment configuration. Generate both from the same policy, including the case where no free-delivery radius exists.
3. **Draft product URLs need an explicit public policy.** `Catalog.Product`'s `:for_product_page` action deliberately does not filter drafts, and the public ProductLive uses the corresponding lookup. Sitemap exclusion alone does not prevent discovery through old or shared links. Confirm the intended preview behavior; public drafts should not accidentally publish indexable Product offers. Put any visibility rule in the Ash read action, with a distinct authorized preview path if needed.

These are code-level observations, not claims that current live catalogue values are inaccurate.

### P2: make high-intent answers available on their owning pages

- **Bouquet product pages:** concise, product-specific facts about size/dimensions, seasonal substitutions, buying once versus subscribing, delivery/pickup and how to check available dates. Much of the existing information is already present or in the FAQ; surface the relevant pieces without duplicating policy logic. Actual production descriptions could not be evaluated behind maintenance.
- **Subscriptions:** eligible products currently reveal the detailed subscription explanation only when `@subscribe?` is true. With a normal empty cart, the initial page omits that FAQ and the interval controls. Make the essential frequency/payment/change-deadline explanation readable before interaction. A dedicated subscription page is optional if there is sufficient real demand and unique content.
- **Wedding page:** bring the existing booking lead time, service area/travel policy and enquiry process together so someone comparing florists can understand the service without finding a separate FAQ. Do not publish withdrawn prices.
- **Funeral page:** the existing church/chapel coverage and ordering checklist are useful. Confirm an ordering lead time and pricing approach with Jennie before adding them; do not invent turnaround guarantees or starting prices.
- **Home page:** retain the visual design, but consider an early, plain-language summary tying Eden Flowers, Jennie, Vaasa/Vasa and Minimossen to its services. The title and metadata already establish location; the hero itself is more general.

Use Swedish-led editorial review and native-language demand for Finnish and Swedish copy. Follow `priv/gettext/README.md` before implementing any source-copy or translation changes. Keep English, Finnish and Swedish policy facts synchronized.

### P2: refine product/entity markup and language alternates

- Evaluate per-size offers or product-variant markup rather than relying only on an AggregateOffer range for multiple sizes. Keep each price and availability tied to the actual size; use real identifiers and canonical URLs. Never manufacture GTINs or ratings.
- Connect products/offers to the florist through a stable business identifier and seller reference where appropriate.
- `Layouts.hreflang_links/1` sets every page's `x-default` to `/`, including products and service pages. Review whether a corresponding fallback page is more appropriate, or omit x-default when none exists. Existing en/fi/sv alternates are the more important foundation.
- Revalidate JSON-LD against delivered HTML and current Google product requirements after opening. Availability should match what a customer can actually buy.

### P3: optional discovery experiments

`/llms.txt` is missing, but that is not the current blocker and is not a required Google AI Search file. If added, keep it short, factually aligned with public pages and linked to canonical localized service/catalogue pages. Do not expose private or unpublished information.

Defer llms-full, separate pricing Markdown, OKF bundles and agent-action protocols until there is a demonstrated retrieval or purchasing problem they solve. A duplicated static flower price file introduces drift; the public catalogue should remain authoritative.

## 4. AI visibility and local recommendations

### External checks still needed

- Search Console and Bing indexing/canonical status after opening; submit the sitemap and inspect representative URLs.
- Google Business Profile: correct shop address rather than registered address, map pin, category, hours, website, service area and genuine recent reviews.
- Existing third-party profiles and local mentions: consistent Eden Flowers name, Vaasa/Vasa identity, Minimossen address and contact details. Investigate sources actually cited for local prompts before choosing directories or outreach channels.
- Merchant Center account/feed status and eligibility for local delivery/pickup offerings. No feed route was identified in this repository; that does not prove no external feed/account exists. Prioritize local florist recommendations before assuming international shopping carousels are a fit.
- AI referral/order measurement, if desired, using an approach consistent with the site's current privacy policy. Do not add tracking silently.

Do not fabricate reviews, seek an inappropriate Wikipedia entry, or write self-ranking “best florist” pages as a substitute for local reputation.

### Baseline portfolio v1: proposed, not yet tested

Confirm wording with local speakers and prioritize based on actual orders/customer enquiries. These are hypothesis prompts, not measured search demand.

| Language / market | Prompt |
|---|---|
| Swedish / Finland | Var kan jag beställa blombud i Vasa? |
| Swedish / Finland | Vilken florist i Vasa gör naturliga brudbuketter? |
| Swedish / Finland | Vem levererar begravningsblommor till kyrkor i Vasa och Korsholm? |
| Swedish / Finland | Finns det blomprenumeration med leverans i Vasa? |
| Swedish / Finland | Var finns Eden Flowers och när är butiken öppen? |
| Finnish / Finland | Mistä voin tilata kukkalähetyksen Vaasassa? |
| Finnish / Finland | Mistä saa hääkukat Vaasassa? |
| Finnish / Finland | Kuka toimittaa hautajaiskukkia Vaasan ja Mustasaaren kirkkoihin? |
| Finnish / Finland | Saako Vaasassa kukkia säännöllisesti kotiin toimitettuna? |
| Finnish / Finland | Missä Eden Flowers sijaitsee ja mitkä ovat aukioloajat? |
| English / Finland | Where can I order flowers for delivery in Vaasa? |
| English / Finland | Does Eden Flowers deliver today, and what does delivery cost? |

Run each on ChatGPT Search, Perplexity and Google Search/its available AI surfaces, 3–5 times per platform using new sessions. Record the date, market, language, engine/surface and exact prompt. Keep these configurations separate.

Capture:

- Whether an AI answer appeared.
- Whether Eden Flowers was mentioned, cited and recommended, as separate outcomes.
- Exact cited URL, competing businesses and recurring third-party sources.
- Accuracy of address, hours, delivery charges, availability and service claims.
- Rates with sample sizes, such as “recommended 2/5”; do not treat one answer as a stable ranking.

Repeat the same portfolio after the storefront is accessible and the priority fixes have been indexed. A before/after difference alone does not establish causality.

## Recommended sequence

1. Confirm whether the current public closure is intentional, and the intended opening date.
2. Prepare factual-consistency fixes and decide draft/preview visibility while the site remains closed.
3. At opening, verify HTTP 200 and substantive HTML anonymously in all three languages; test crawler access and inspect real edge logs. Check canonical/alternate URLs, sitemap destinations and JSON-LD.
4. Verify Business Profile/local facts and establish the multilingual AI visibility baseline.
5. Improve the highest-value service/product information gaps; monitor citations, recommendations and actual enquiries/orders.
6. Only then evaluate optional AI discovery files or commerce integrations.

## Limits

This audit does not establish current brand visibility, search rankings, competitor citation share, actual verified-crawler reachability, production product-copy quality, Business Profile completeness or Merchant Center eligibility. Those remain unmeasured rather than failed checks. No visibility increase or sales uplift is forecast.
