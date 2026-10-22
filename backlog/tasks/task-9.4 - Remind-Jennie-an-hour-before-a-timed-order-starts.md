---
id: TASK-9.4
title: Remind Jennie an hour before a timed order starts
status: done
assignee: []
created_date: '2026-10-22 06:36'
updated_date: '2026-10-22 06:36'
labels: []
dependencies: []
parent_task_id: TASK-9
type: feature
ordinal: 187000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** an order with a time or window is easy to lose track of on a busy day; a nudge an hour before means she isn't late for it.

### What was built

- Every 5 minutes, an AshOban trigger finds placed, still-pending orders with a time or window that starts within the next hour and haven't been reminded. Each gets one reminder (`shop_reminded_at`), by email and push like a new order.
- Deliveries and pickups both. An order with only a date gets none.
- Only within that hour, so orders long past never fire on deploy.
- Title: "Leverans kl. 12.00, beställning 1042" or "Avhämtning kl. 12.00–16.00, beställning 1042". On her phone it replaces that order's new-order notification.
- An order rescheduled after its reminder isn't reminded again.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An order starting within the hour reminds the shop once, by email and push
- [x] #2 Orders outside the hour, without a time, already fulfilled or already reminded get no reminder
<!-- AC:END -->
