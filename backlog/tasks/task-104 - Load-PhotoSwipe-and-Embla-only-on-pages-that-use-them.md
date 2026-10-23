---
id: TASK-104
title: Load PhotoSwipe and Embla only on pages that use them
status: needs-triage
assignee: []
created_date: '2026-10-23 07:51'
updated_date: '2026-10-23 07:59'
labels:
  - customers
  - spec
dependencies: []
priority: low
type: task
ordinal: 213000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The gallery and carousel libraries download only on the pages that show a gallery or the featured carousel.

**Why:** PhotoSwipe (75 KB minified) and Embla (18 KB) make up a third of the bundle every shopper downloads, though only the weddings, condolences and home pages use them. That is about 25 KB gzipped saved on every other page.

**What:** turn on esbuild `--splitting --format=esm`, load app.js as `type="module"`, and have PhotoGallery and FeaturedCarousel `await import()` their library on mount. Phoenix LiveView and Phoenix (about 45 KB gzipped) are the floor and stay.

**Open:** measure first with a mobile Lighthouse run on a production build, to see whether 25 KB gzipped changes anything a shopper feels. Images likely dominate LCP. Stripe.js stays a deferred classic script in the head (loaded site-wide for Radar), so check the Stripe hook still finds `window.Stripe` once app.js is a module script.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Pages without a gallery or carousel do not download PhotoSwipe or Embla
- [ ] #2 The weddings and condolences galleries and the home carousel work, including after live navigation to them
<!-- AC:END -->
