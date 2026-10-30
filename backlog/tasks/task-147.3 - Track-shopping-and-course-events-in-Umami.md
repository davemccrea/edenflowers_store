---
id: TASK-147.3
title: Track shopping and course events in Umami
status: done
assignee: []
created_date: '2026-10-30 17:41'
updated_date: '2026-10-30 20:58'
labels: []
dependencies: []
parent_task_id: TASK-147
type: feature
ordinal: 284000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Events show where people drop out and which sources bring revenue. Add to cart, Checkout started, Checkout step reached, Delivery not available, Promo code applied/rejected, Order completed, Subscription started, Newsletter signup, Send a gift, Course booking started, Course booked. Once-per-id events dedupe in localStorage.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each listed event fires with its data
- [x] #2 Order completed, Checkout started and Course booked fire once per id
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Send a gift is not tracked: main removed the button (72478e9d) while this was in progress. Other events checked in the browser with a stubbed umami.track.
<!-- SECTION:NOTES:END -->
