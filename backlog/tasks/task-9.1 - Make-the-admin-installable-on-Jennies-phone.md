---
id: TASK-9.1
title: Make the admin installable on Jennie's phone
status: done
assignee: []
created_date: '2026-10-15 23:06'
updated_date: '2026-10-18 07:27'
labels: []
dependencies: []
parent_task_id: TASK-9
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

Let Jennie add the admin to her phone's home screen so it opens full-screen on the dashboard, separately from the storefront. Tidy the storefront manifest at the same time.

- **Admin manifest:** a second manifest, `priv/static/admin.webmanifest`, linked only from admin pages. The root layout keeps linking `site.webmanifest` for everything else.
  - `name: "Eden Flowers Admin"`, `short_name: "Eden Admin"`
  - `id: "/admin"`, `scope: "/admin"`, `start_url: "/admin"`
  - `display: "standalone"`, same `theme_color` and `background_color` as the storefront
  - Same icons as the storefront (see below). A distinct admin icon is out of scope.
- **Choosing the manifest:** `root.html.heex` is shared, so pick the manifest from the request path (`/admin` prefix → admin manifest). Add `admin.webmanifest` to `static_paths` in `lib/edenflowers_web.ex`.
- **Storefront manifest fixes** (`priv/static/site.webmanifest`):
  - Add `id: "/"`, `start_url: "/"`, `scope: "/"`.
  - Both icons are `"purpose": "maskable"` only. Add `"any"` entries for the 192 and 512 icons, so launchers that don't mask still get a clean icon. If the current PNGs have no safe-zone padding, `maskable` entries need separately padded files; check how the PNGs look before reusing them for both.
- **Theme colour:** add `<meta name="theme-color" content="#BDCCC3">` to the root layout.
- Bump the `?v=` cache-buster on the manifest links. Cloudflare caches static files.

No service worker in this issue. Chrome and Safari both install without one now.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 On an admin page, the page links `admin.webmanifest`; on storefront pages it links `site.webmanifest`
- [ ] #2 Adding to Home Screen from an admin page on iOS Safari and Android Chrome installs "Eden Admin", which opens `/admin` with no browser chrome
- [ ] #3 Links to storefront pages from the installed admin app open in the browser, not inside the app (outside `scope`)
- [ ] #4 The storefront still installs as "Eden Flowers" and opens `/`
- [ ] #5 Chrome DevTools > Application > Manifest shows no warnings for either manifest
- [ ] #6 Mobile browser bars take the sage theme colour
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @david
created: 2026-10-17 18:45

---

Implemented 2026-10-15. The PNGs are full-bleed sage squares with the mark well inside the safe zone, so the same files serve as both `any` and `maskable`. Installing on a real phone is still to check by hand.

---
<!-- COMMENTS:END -->
