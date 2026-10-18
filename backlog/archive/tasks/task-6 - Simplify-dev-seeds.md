---
id: TASK-6
title: Simplify dev seeds
status: done
assignee: []
created_date: '2026-10-10 22:45'
updated_date: '2026-10-18 05:33'
labels: []
dependencies: []
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cut the dev seeds down to the fixtures that put a screen into a state someone actually checks

`priv/repo/seeds.exs` is ~1,250 lines on top of `priv/repo/seeds/production.exs`. Which fixtures go is the owner's call: see `TASK-6.1`.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Cut seeds.exs from 1,335 to 956 lines (dacc8811): one example of each feature or variation. Products, online and subscription orders share helpers; duplicate products, courses, expenses, orders, Helena's subscription and the Sara Björk, Kalle and Henrik custom orders were removed. No counter MobilePay or Zettle payment is seeded any more.
<!-- SECTION:NOTES:END -->
