---
id: TASK-121
title: 'Derive every order, subscription and booking state from the Ash domain'
status: in-progress
assignee: []
created_date: '2026-10-25 10:08'
updated_date: '2026-10-25 10:08'
labels:
  - spec
  - developers
dependencies: []
priority: medium
type: refactor
ordinal: 240000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
No LiveView or controller works out an order's, subscription's or course booking's state itself: each reads a calculation, aggregate or relationship on the resource, and the actions validate against the same ones.

**Why:** The web layer re-derives rules the domain already has (cancellable, deletable, upcoming, overdue, the next occurrence), and some copies have drifted: the account timeline's 'upcoming' course disagrees with CourseRegistration.upcoming?. One rule in one place stops that.

Decisions (grilled 2026-10-25):
- Keep in the web layer only what is presentation: gettext labels for a status atom, checkout step routing, list splitting for display, copy that quotes constants.
- Customer order status becomes an enum calculation; account_live only maps it to a label.
- CourseRegistration.upcoming? wins over the timeline's date-only rule.
- The cancel drawer's suggested refund becomes a refund_on_cancelling calculation on both payables, and :cancel uses it when no refund is given.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No web module compares state, status, fulfillment_status or payment_status to decide what an order, subscription or booking can do or is
<!-- AC:END -->
