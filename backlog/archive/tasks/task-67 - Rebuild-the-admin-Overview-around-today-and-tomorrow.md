---
id: TASK-67
title: Rebuild the admin Overview around today and tomorrow
status: done
assignee: []
created_date: '2026-10-20 06:52'
updated_date: '2026-10-21 12:33'
labels:
  - spec
  - admin
dependencies: []
priority: high
type: feature
ordinal: 141000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The Overview answers what Jennie needs right now: what's wrong, what to make today and tomorrow, and what the coming week looks like, with money and reporting below.

**Why:** Jennie opens the Overview on her phone many times a day, and today it lists every open order weeks ahead at equal weight, so today's work is buried and the things that need her are scattered.

### Decisions

- Phone first; desktop gets a suitable two-column layout, but every section is designed at phone width first.
- Top to bottom: Needs attention, Today, Tomorrow, The week ahead, Upcoming courses, Open balances, This month. The accountant report only appears early in the month.
- Orders further out than tomorrow aren't listed; the week ahead summarises them and "View all orders" covers the rest.
- No "Mark fulfilled" on the Overview: fulfilling stays on the order page, where she checks the card message.
- The make list counts products and sizes, not stems. Wholesale buying is done anywhere from a day to a week ahead and Jennie is flexible, so no recipe data.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
To collect left the Overview (2026-10-20): what's owed but not overdue needs no action, and today's and tomorrow's rows already badge unpaid orders. This month shows the total still owed on orders as one line instead.
<!-- SECTION:NOTES:END -->
