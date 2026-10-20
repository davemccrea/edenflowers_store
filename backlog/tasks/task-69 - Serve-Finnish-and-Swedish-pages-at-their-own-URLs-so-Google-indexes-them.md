---
id: TASK-69
title: Serve Finnish and Swedish pages at their own URLs so Google indexes them
status: ready-for-agent
assignee: []
created_date: '2026-10-20 10:12'
updated_date: '2026-10-20 10:20'
labels:
  - spec
  - customers
dependencies: []
priority: high
type: feature
ordinal: 151000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Each language gets its own URL under /fi, /sv and /en, with hreflang links between the versions, so search engines can index and rank every language.

**Why:** Today one URL serves English, Finnish or Swedish depending on the session and the browser's Accept-Language. Googlebot sends no language preference, so only the English pages get indexed, and people searching "kukkakauppa Vaasa" or "blomsterhandel Vasa" land on English pages or don't find the shop at all.

### Decisions

- **All three languages are prefixed**: /fi/..., /sv/..., /en/... No language gets the bare URLs.
- **Path segments are translated** through `priv/gettext/<locale>/LC_MESSAGES/routes.po`, e.g. /fi/haat, /sv/brollop, /fi/kauppa/kimput, /sv/butik/buketter. Jennie reviews the Finnish and Swedish words before launch, since URLs are costly to change once indexed. Product and course ids stay as they are.
- **Only public, indexable pages are localized**: home, weddings, condolences, about, contact, FAQ, store categories, products, courses and course pages. Checkout, account, order, pay, booking, sign-in and admin keep their current unprefixed URLs and use the session locale, which visiting a prefixed page sets. Email links to orders and payments don't change.
- **Bare / and old unprefixed public URLs redirect by preference**: session locale, then Accept-Language, then Finnish. A 302 with `Vary: Accept-Language, Cookie`, since the target depends on the visitor. Prefixed URLs never redirect, so crawlers see each language as it is. hreflang `x-default` points at /.

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
- [ ] #1 Every public page has a URL per language and renders in that language with no session or Accept-Language
- [ ] #2 Each public page has hreflang alternates for en, fi, sv and x-default, and a canonical pointing at its own language URL
- [ ] #3 The sitemap lists every language version
- [ ] #4 The language switcher links to the same page in the other language
- [ ] #5 Bare / and old unprefixed public URLs redirect (302) to the visitor's session language, else Accept-Language, else Finnish
- [ ] #6 Checkout, account, order, pay and booking URLs are unchanged and render in the session language
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-20 10:20

---

Decided with David: prefix all three languages, translate path segments, localize public pages only, redirect bare / by session then Accept-Language then Finnish.

---
<!-- COMMENTS:END -->
