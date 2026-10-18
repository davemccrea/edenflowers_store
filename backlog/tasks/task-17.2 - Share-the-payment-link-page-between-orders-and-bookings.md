---
id: TASK-17.2
title: Share the payment-link page between orders and bookings
status: ready-for-agent
assignee: []
created_date: '2026-10-18 03:08'
labels: []
dependencies:
  - TASK-17.1
parent_task_id: TASK-17
type: refactor
ordinal: 49000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

`TASK-17` decision 5.

- A component (or function components plus a small helper module) holding the Stripe Elements mount, the `pay` handler's freshness checks, `sync_amount`, `maybe_flash_failed_payment` and the paid, settled and cancelled states.
- `PayLive` and `CoursePayLive` keep their own mount (token lookup, locale, PubSub topic), summary and copy, and delegate the rest.
- Consider whether `ReceiptController` and `CourseReceiptController` can become one controller, since `Receipt.generate/1` already takes either record. Do it only if the routes stay as they are.

### Tests

- The existing LiveView tests for both pages pass unchanged.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The payment flow code exists once
- [ ] #2 The existing suite passes
<!-- AC:END -->
