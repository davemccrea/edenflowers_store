---
id: TASK-147
title: Self-host Umami for cookieless site analytics
status: in-progress
assignee: []
created_date: '2026-10-30 09:38'
updated_date: '2026-10-30 17:41'
labels:
  - spec
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 280000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Run self-hosted Umami so the shop can see where visitors come from and which pages and campaigns lead to orders, without cookies or a consent banner.

**Why:** Today there are no site analytics, so there is no way to tell which Instagram/Facebook posts, emails or pages bring in orders, or where people drop out of checkout. Umami is free, cookieless (no banner needed) and runs on the Postgres we already host, unlike Plausible CE, which needs ClickHouse and lacks funnels and revenue tracking.

Decisions (grilled 2026-10-30):
- Served at `stats.edenflowers.fi` through the existing Cloudflare tunnel, like Papra. Tracker script and collect endpoint renamed (`TRACKER_SCRIPT_NAME`, `COLLECT_API_ENDPOINT`) so ad blockers do not match them.
- Compose service on `network_mode: host`, image pinned to a major Postgres tag (not `:latest`). Own `umami` database and role on the host Postgres, included in the nightly dump and off-site mirror.
- Script in the root layout only when `UMAMI_WEBSITE_ID` is set (so prod only), skipped on `/admin` and for signed-in admin users.
- Events: Add to cart (product), Checkout started (once per order), Checkout step reached (step), Delivery not available (reason), Promo code applied/rejected (code), Order completed (once per order, revenue incl. VAT, EUR), Subscription started (revenue), Newsletter signup, Send a gift, Course booking started, Course booked (once per booking, revenue). Revenue and attribution events fire client-side so they keep the referrer/UTM; once-per-id dedupe in localStorage.
- Privacy page names Umami as self-hosted and cookieless (en/fi/sv; fi/sv for David to review).
- Funnels are configured in the Umami UI, no code.
- Out of scope: custom retention, server-side events, wedding/contact enquiry events.

Rollout: provision Umami, add the tunnel hostname, create the website in Umami, put its ID in vars, provision again, deploy the app.

Open: confirm the server RAM fits Umami (~200-300 MB) alongside app, imgproxy and Papra.
<!-- SECTION:DESCRIPTION:END -->
