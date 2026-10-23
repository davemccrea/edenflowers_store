---
id: TASK-101
title: Load Stripe.js once the page is idle
status: ready-for-human
assignee: []
created_date: '2026-10-22 21:05'
updated_date: '2026-10-23 09:39'
labels:
  - customers
  - spec
  - quick
dependencies: []
priority: medium
type: task
ordinal: 210000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** the root layout loads Stripe.js (268 KB) with defer ahead of app.js on every page, so LiveView cannot connect until Stripe has downloaded and run. Lighthouse mobile on production (2026-10-23, two runs each) put pages interactive at 5.0-5.2 s with it and 2.8-3.7 s without it, and the store's LCP at 5.0 s vs 3.7 s.

**Decisions** (grilled 2026-10-23):
- Stripe.js stays on every page, as Stripe advises for Radar's fraud signals, but loads after the window load event, in requestIdleCallback with a 2 s timeout (setTimeout where Safari lacks it).
- assets/js/stripe.js exports loadStripe(): adds the script tag once and returns the same promise. app.js calls it when idle; the colocated Stripe hook imports it as @/js/stripe and awaits it on mount, so a payment page loads it at once if idle has not come yet.
- A failed load goes through the hook's existing catch: logged, stripe:error pushed, button re-enabled. Elsewhere a failure is silent.
- The script tag and its comment leave root.html.heex. No preconnect hint.
- Re-measure production after the next deploy.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 LiveView connects without waiting for Stripe.js: no Stripe.js script tag in the page HTML, one added once the page is idle
- [ ] #2 The Payment Element mounts on checkout, course registration, payment links and the subscription card, opened directly and after live navigation
- [x] #3 A Stripe.js load failure shows the error and re-enables the pay button
- [x] #4 mix test passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Checked in headless Chrome on dev: /en HTML has no Stripe.js tag, exactly one is added once idle; a payment link opened directly mounts the Payment Element with one tag; a course opened by live navigation from /en/courses mounts it after booking; with js.stripe.com blocked the pay button re-enables and the existing "payment temporarily unavailable" message shows. A failed load resets the loader so a payment form can retry. Checkout and the subscription card share the same stripe_form but were not clicked through to their payment step.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-23 07:59

---

Stripe.js stays on every page: Stripe advises loading it site-wide so Radar sees browsing signals for fraud detection, which is why the root layout loads it. That is worth more than the third-party cost on browsing pages.

---

author: @claude
created: 2026-10-23 09:25

---

Reopened 2026-10-23: the TASK-104 measurement showed Stripe.js is the largest script cost on every page (268 KB transfer, 144-156 ms script time on Lighthouse mobile, about 3x app.js), so it is worth weighing against Radar after all.

---

author: @claude
created: 2026-10-23 09:39

---

Left for a human: pay through checkout and the subscription card with a Stripe test card, then check AC #2. After the next deploy, re-run the production Lighthouse comparison (needs a sign-in code).

---
<!-- COMMENTS:END -->
