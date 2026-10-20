---
id: TASK-71
title: 'Redirect http://edenflowers.fi to https'
status: done
assignee: []
created_date: '2026-10-20 10:12'
updated_date: '2026-10-20 17:40'
labels:
  - spec
  - customers
  - quick
dependencies: []
priority: medium
type: bug
ordinal: 153000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Plain-http requests redirect to https before reaching the app.

**Why:** `http://edenflowers.fi/` is served over http today (it redirected to http://edenflowers.fi/back-soon), so a typed or old http link opens an insecure page and search engines can see two copies of every URL.

Turn on **SSL/TLS > Edge Certificates > Always Use HTTPS** in Cloudflare for edenflowers.fi. The app has no `force_ssl`; adding it would also need `x-forwarded-proto` handling behind Cloudflare, so the Cloudflare setting is the smaller fix. HSTS is optional and hard to undo, so leave it until https has been solid for a while.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `curl -sI http://edenflowers.fi/some/path` returns 301 to `https://edenflowers.fi/some/path`
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-20 17:40

---

Verified: http://edenflowers.fi/some/path and http://www.edenflowers.fi/ both 301 to their https URLs.

---
<!-- COMMENTS:END -->
