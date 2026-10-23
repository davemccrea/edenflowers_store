---
id: TASK-101
title: Load Stripe.js only on pages that take payment
status: done
assignee: []
created_date: '2026-10-22 21:05'
updated_date: '2026-10-23 07:59'
labels:
  - customers
  - spec
  - wontfix
dependencies: []
priority: low
type: task
ordinal: 210000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** components/layouts/root.html.heex loads Stripe.js on every page, including marketing pages. Shoppers who are only browsing pay for a script larger than our whole app.js bundle (270 KB minified, 84 KB gzipped) plus the hidden fraud-signals iframe it starts.

Not measured yet: the SEO audit (2026-10-20) found no actual Core Web Vitals regression. Profile a production build on mobile first, with and without Stripe.js, and only go ahead if it costs something real.

**Proposed approach** (from a 2026-10-23 review):
- Every payment form goes through `stripe_form` (core_components.ex): checkout, course registration, payment links and the subscription card. So the change lives in one place.
- The `Stripe` hook loads Stripe.js itself: if `window.Stripe` is missing, it adds the `js.stripe.com/v3` script tag, waits for it, then runs the existing setup. One shared loading promise, so mounting twice never loads it twice. Drop the tag from the root layout.
- It has to be the hook, not a conditional tag in the root layout: live navigation (cart to checkout) never re-renders the root layout.
- `stripe_form` adds `<link rel="preconnect" href="https://js.stripe.com">`, so the connection starts while LiveView connects.
- A script that fails to load (ad blocker, network) goes through `logAndPushError`, so the pay button does not stay loading forever.

**Open:** Stripe advises loading Stripe.js on every page so Radar sees more browsing signals. Loading it only for payment gives Radar less to go on, though it still scores every payment. Most payments here are MobilePay or 3-D Secure cards, so the loss looks small. Decide whether chargebacks or fraud have been a problem before dropping it.

Pairs with the colocated hooks spec: the `Stripe` hook could be the first one moved, with the loader in it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A mobile profile of the production build says whether Stripe.js on non-payment pages costs anything measurable
- [ ] #2 Payment initialisation still works on checkout, course registration, payment links and the subscription card, including after live navigation into them
- [ ] #3 A Stripe.js load failure shows an error instead of a stuck pay button
- [ ] #4 Pages without a stripe_form make no request to js.stripe.com
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-23 07:59

---

Stripe.js stays on every page: Stripe advises loading it site-wide so Radar sees browsing signals for fraud detection, which is why the root layout loads it. That is worth more than the third-party cost on browsing pages.

---
<!-- COMMENTS:END -->
