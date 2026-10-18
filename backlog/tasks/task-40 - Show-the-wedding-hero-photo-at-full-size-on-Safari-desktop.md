---
id: TASK-40
title: Show the wedding hero photo at full size on Safari desktop
status: ready-for-human
assignee: []
created_date: '2026-10-18 18:22'
updated_date: '2026-10-18 20:04'
labels:
  - spec
  - customers
dependencies: []
priority: low
type: bug
ordinal: 101000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The Anna Riska photo is the first thing a couple sees on the wedding page, and on Safari desktop it looks small.

Reproduce on `weddings_live.ex` in WebKit at desktop widths, find what sizes the hero image differently from Chromium (likely an aspect-ratio, `object-fit` or grid sizing difference) and fix it.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 On Safari desktop the hero photo fills its area as it does in Chrome
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Could not reproduce in Playwright WebKit 26.6 (DPR 1 and 2, direct load, LiveView nav, reload): sizes matched Chrome. The hero's desktop width came from md:w-auto, i.e. the browser's density-corrected natural size of the srcset image, capped by max-height. Now the width is set from the same height cap times the aspect ratio (max-w-full clamps to the column), so no browser sizes it from the image. Same change on the condolences hero. Layout in Chrome and WebKit is unchanged at 1024-1920px wide and on phones.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-18 18:22

---

Reproduce in Playwright's WebKit; the final check is on Jennie's own Safari.

---

author: @claude
created: 2026-10-18 20:04

---

Check on Jennie's Safari: open /weddings (and /condolences) at full window width after this deploys to staging. The hero photo should reach from just under the header to near the bottom of the window, about as wide as the right-hand column, same as in Chrome. If it still looks small, note the window size and the image's width (Develop > Show Web Inspector) so we can see what differs.

---
<!-- COMMENTS:END -->
