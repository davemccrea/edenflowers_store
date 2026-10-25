---
id: TASK-41
title: Lead the wedding hero with See my work and Estimate your price
status: done
assignee: []
created_date: '2026-10-18 18:22'
updated_date: '2026-10-18 18:41'
labels:
  - spec
  - customers
  - quick
dependencies: []
priority: low
type: feature
ordinal: 102000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The hero's main button asks for a quote before the couple has seen anything. Showing the work first, then the estimator that ends in its own Request a quote, asks at the moment they're ready.

In `weddings_live.ex`, the hero's buttons become **See my work** (primary, `#my-work`) and **Estimate your price** (secondary, `#prices`). The Request a quote buttons after the estimator and at the bottom stay.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The hero's primary button is See my work and scrolls to the gallery
- [x] #2 Next to it, Estimate your price scrolls to the estimator
- [x] #3 The hero no longer has a Request a quote button
<!-- AC:END -->
