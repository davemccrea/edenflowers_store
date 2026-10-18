---
id: TASK-40
title: Show the wedding hero photo at full size on Safari desktop
status: ready-for-agent
assignee: []
created_date: '2026-10-18 18:22'
updated_date: '2026-10-18 18:22'
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

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-18 18:22

---

Reproduce in Playwright's WebKit; the final check is on Jennie's own Safari.

---
<!-- COMMENTS:END -->
