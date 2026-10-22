---
id: TASK-101
title: Load Stripe.js only on pages that take payment
status: needs-triage
assignee: []
created_date: '2026-10-22 21:05'
labels:
  - customers
dependencies: []
priority: low
type: task
ordinal: 210000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** components/layouts/root.html.heex loads Stripe.js on every page, including marketing pages, which adds third-party work for shoppers who are only browsing.

Not measured yet: the SEO audit (2026-10-20) found no actual Core Web Vitals regression. Open question: profile a production build on mobile first, and only move Stripe.js to the checkout and payment pages if it costs something real. Keep payment initialisation working wherever Stripe is used.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A mobile profile of the production build says whether Stripe.js on non-payment pages costs anything measurable
<!-- AC:END -->
