---
id: TASK-69
title: Serve Finnish and Swedish pages at their own URLs so Google indexes them
status: done
assignee: []
created_date: '2026-10-20 10:12'
updated_date: '2026-10-20 17:50'
labels:
  - spec
  - customers
dependencies: []
priority: high
type: feature
ordinal: 160000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Each language gets its own URL under /fi, /sv and /en, with hreflang links between the versions, so search engines can index and rank every language.

**Why:** Today one URL serves English, Finnish or Swedish depending on the session and the browser's Accept-Language. Googlebot sends no language preference, so only the English pages get indexed, and people searching "kukkakauppa Vaasa" or "blomsterhandel Vasa" land on English pages or don't find the shop at all.

### Decisions

- **All three languages are prefixed**: /fi/..., /sv/..., /en/... No language gets the bare URLs.
- **Path segments are translated** through `priv/gettext/<locale>/LC_MESSAGES/routes.po`, e.g. /fi/haat, /sv/brollop, /fi/kauppa/kukkakimput, /sv/butik/buketter. Category slugs are translated like the category name, in its `translations` (`slug` stays the English slug and the fallback). Jennie reviews the Finnish and Swedish words before launch, since URLs are costly to change once indexed. Product and course ids stay as they are.
- **Only public, indexable pages are localized**: home, weddings, condolences, about, contact, FAQ, store categories, products, courses and course pages. Checkout, account, order, pay, booking, sign-in and admin keep their current unprefixed URLs and use the session locale, which visiting a prefixed page sets. Pay pages use the order's or booking's language. Email links to orders and payments don't change.
- **Bare / redirects by preference**: session locale, then Accept-Language, then Swedish. A 302 with `Vary: Accept-Language, Cookie`, since the target depends on the visitor. Prefixed URLs never redirect, so crawlers see each language as it is. hreflang `x-default` points at /.

### Approach

`localize_web` (already a dependency) does most of this:

- `use Localize.Routes` and wrap the public routes in `localize do ... end` in the router, with the locale as a path prefix. It supports `live` routes.
- The `~q` sigil (`Localize.VerifiedRoutes`) builds links for the current locale; `path_for/2` and `url_for/2` build them for another locale (language switcher, hreflang).
- The generated `*_links` helpers plus `hreflang_links/1` render `<link rel="alternate" hreflang>` tags in the root layout.
- `Localize.Plug.PutLocale` reads the locale from the route first on public pages, and the session keeps it for the unprefixed private pages.

Also update: the canonical link (per language), `<html lang>`, the sitemap (one entry per language), the language switcher (link to the same page in the other language instead of `/locale/:locale`; keep `/locale/:locale` for the unprefixed private pages), links in the nav, footer and emails that point at public pages, and robots.txt paths if any change.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every public page has a URL per language and renders in that language with no session or Accept-Language
- [x] #2 Each public page has hreflang alternates for en, fi, sv and x-default, and a canonical pointing at its own language URL
- [x] #3 The sitemap lists every language version
- [x] #4 The language switcher links to the same page in the other language
- [x] #5 Bare / redirects (302) to the visitor's session language, else Accept-Language, else Swedish
- [x] #6 Checkout, account, order, pay and booking URLs are unchanged and render in the session language
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-20 10:20

---

Decided with David: prefix all three languages, translate path segments, localize public pages only, redirect bare / by session then Accept-Language then Finnish.

---

author: @claude
created: 2026-10-20 11:15

---

Built. Fallback language changed to Swedish (Edenflowers.Locales.default is now sv-FI). Category slugs are translated in the category's translations, with slug as the English key and fallback. Left before launch: (1) Jennie reviews the URL words in priv/gettext/{fi,sv}/LC_MESSAGES/routes.po (fi: haat, hautajaiset, tietoa, yhteystiedot, ukk, kauppa, tuote, kurssit; sv: brollop, begravning, om, kontakt, vanliga-fragor, butik, produkt, kurser) and the category slugs (bouquets kukkakimput/buketter, plants kasvit/vaxter, cards kortit/kort, pre-loved kaytetty/begagnat). (2) Set those category slugs on the production categories' translations; priv/repo/seeds/production.exs only covers an empty database.

---
<!-- COMMENTS:END -->
