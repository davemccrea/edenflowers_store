---
id: TASK-84.3
title: Show a product's photos as a gallery on its store page
status: done
assignee: []
created_date: '2026-10-21 15:35'
updated_date: '2026-10-21 15:50'
labels: []
dependencies:
  - TASK-84.1
parent_task_id: TASK-84
type: feature
ordinal: 172000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** customers see the bouquet from every angle Jennie photographed, and choosing a size still shows what that size looks like.

- Under the product photo, a row of thumbnail buttons, one per photo, hidden when there is only one. Clicking a thumbnail shows that photo; the current one is marked (`aria-pressed` or `aria-current`).
- A thumbnail never changes the selected size or the price.
- Choosing a size shows its photo, or the main photo when it has none.
- Plain buttons handled by the LiveView; no carousel or new dependency. Must fit one row at phone width with 8 photos.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A product with several photos shows a thumbnail row; one with a single photo looks as it does today
- [x] #2 Clicking a thumbnail swaps the photo without changing size or price
- [x] #3 Choosing a size shows its photo, or the main photo when it has none
- [x] #4 The thumbnails are keyboard reachable and announce which photo is shown
<!-- AC:END -->
