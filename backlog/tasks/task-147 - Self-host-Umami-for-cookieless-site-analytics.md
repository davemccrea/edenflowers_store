---
id: TASK-147
title: Self-host Umami for cookieless site analytics
status: needs-triage
assignee: []
created_date: '2026-10-30 09:38'
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

**Why:** Today there are no site analytics, so there's no way to tell which Instagram/Facebook posts, emails or pages bring in orders, or where people drop out of checkout. Umami is free, cookieless (no banner needed) and runs on the Postgres we already host, unlike Plausible CE, which needs ClickHouse and lacks funnels and revenue tracking.

Rough shape:
- Umami container in the compose services under `infra/`, with its own database on the host Postgres
- Tracking script in the root layout, skipped on admin pages
- Custom events for key steps (e.g. started checkout, order completed, newsletter signup, Send a gift)
- Privacy page cookies section updated to mention cookieless, self-hosted analytics (en/fi/sv)

Open questions:
- Which subdomain serves Umami, and does it go through Cloudflare?
- Which events and funnels matter?
- Do we exclude admin/staff visits, and how?
- Does it fit in the server's RAM alongside the current services?
<!-- SECTION:DESCRIPTION:END -->
