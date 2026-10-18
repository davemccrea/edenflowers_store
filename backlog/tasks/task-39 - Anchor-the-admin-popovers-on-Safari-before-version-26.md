---
id: TASK-39
title: Anchor the admin popovers on Safari before version 26
status: ready-for-agent
assignee: []
created_date: '2026-10-18 18:22'
updated_date: '2026-10-18 18:22'
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
- [ ] #1 On a browser without anchor positioning, the ⋯ menu opens next to its button
- [ ] #2 The course payment-link popup opens next to its button
- [ ] #3 Browsers with anchor positioning behave as today
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-18 18:22

---

Reproduce in Playwright's WebKit if it lacks anchor positioning; the final check is on Jennie's own Safari.

---
<!-- COMMENTS:END -->
