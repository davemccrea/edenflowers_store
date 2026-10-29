---
id: TASK-141.1
title: Show today's order status in the bar
status: done
assignee: []
created_date: '2026-10-28 20:53'
updated_date: '2026-10-29 03:27'
labels: []
dependencies: []
parent_task_id: TASK-141
type: feature
ordinal: 275000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Answers "can I still get flowers today?" on every storefront page, and is what the bar shows when nothing else applies. Replaces the homepage's "Next available day" row.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every :public storefront page shows the bar with the right state for the shop calendar
- [x] #2 The bar updates without a reload once today's order deadline passes
- [x] #3 The homepage Delivery and pickup section no longer has a Next available day row
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Bar renders inside the fixed header (#hotfx-shy-header); main gets --order-status-bar-height of top padding (except under an opening photo) so every page's own header clearance holds. PutOrderStatus hook (:public live session) reuses Availability.next_open_date and refreshes every minute. sv/fi strings are agent drafts awaiting native review.
<!-- SECTION:NOTES:END -->
