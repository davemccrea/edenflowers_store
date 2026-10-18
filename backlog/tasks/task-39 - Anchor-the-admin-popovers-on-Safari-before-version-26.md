---
id: TASK-39
title: Anchor the admin popovers on Safari before version 26
status: ready-for-human
assignee: []
created_date: '2026-10-18 18:22'
updated_date: '2026-10-18 20:00'
labels:
  - spec
  - admin
dependencies: []
priority: medium
type: bug
ordinal: 100000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** On Jennie's Safari the ⋯ menus and the course payment-link popup open in the middle of the screen like a modal, so she loses track of which row she's acting on.

The popover in `admin/components/components.ex` positions itself with CSS anchor positioning (`anchor-name`), which Safari supports only from 26. Without it a popover falls back to the centre of the viewport. Add a fallback under `@supports not (anchor-name: --a)` that places the popover next to its trigger (for example a small hook that sets its position from the trigger's rect on toggle). Check that the course payment-link popup is the same component and is fixed by the same change.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 On a browser without anchor positioning, the ⋯ menu opens next to its button
- [x] #2 The course payment-link popup opens next to its button
- [x] #3 Browsers with anchor positioning behave as today
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Fallback for browsers without anchor positioning: app.js records the ⋯ button's position on <html> (LiveView rewrites the menu's own style) on beforetoggle, and admin.css under @supports not (position-area: bottom) places the menu below the button's right edge and drops daisyUI's modal backdrop. The course payment-link actions are in the same actions_menu, so the same fix covers them. Verified in Chromium at 390px by simulating no anchor support (CSS.supports stubbed, daisyUI's @supports not rules forced on, position-area stripped): menus open under their button, same place as native (1px off). Native Chromium unchanged. Playwright here has no WebKit. Known limit: in the fallback the menu stays put if the page is scrolled with a wheel while it's open.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-18 18:22

---

Reproduce in Playwright's WebKit if it lacks anchor positioning; the final check is on Jennie's own Safari.

---

author: @claude
created: 2026-10-18 20:00

---

Check on Jennie's Safari (pre-26, e.g. iOS/macOS Safari 18): open Admin > Courses, expand a course, tap a booking's ⋯ menu. It should open just below the button, right-aligned to it, with no dark backdrop, not centred on screen. Also tap ⋯ in an order or expense page header.

---
<!-- COMMENTS:END -->
