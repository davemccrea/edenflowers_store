---
id: TASK-15.2
title: Let a customer pay a booking's payment link on its own page
status: done
assignee: []
created_date: '2026-10-17 18:41'
updated_date: '2026-10-19 20:30'
labels: []
dependencies:
  - TASK-15.1
parent_task_id: TASK-15
type: feature
ordinal: 44000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

Spec decision 4.

- `/courses/pay/:token`, a LiveView in the courses feature, in the booking's locale: course, date, seats, paid, owed, and the Payment Element through `Payments.setup/2`. Paid, it shows that; an unknown token flashes and redirects home, as `PayLive` does.
- Subscribes to the booking's paid broadcast so the page updates when the webhook lands.
- New copy through gettext, with en, fi and sv msgstrs.

### Tests

- The page shows what's owed and never other bookings' details; an unknown token redirects.
- A settled booking's page says it's paid and offers no payment.
- Returning from Stripe with a succeeded redirect shows the paid state once the payment is recorded.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Every case above passes
- [x] #2 The existing suite passes
<!-- AC:END -->
