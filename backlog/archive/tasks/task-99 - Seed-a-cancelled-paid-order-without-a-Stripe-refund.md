---
id: TASK-99
title: Seed a cancelled paid order without a Stripe refund
status: done
assignee: []
created_date: '2026-10-22 19:54'
updated_date: '2026-10-22 20:13'
labels:
  - wontfix
dependencies: []
priority: high
type: bug
ordinal: 204000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`mix run priv/repo/seeds.exs` finishes again, so new worktrees get a seeded database.

**Why:** Every `wt switch --create` fails at the seed step and leaves an empty dev database, so nothing can be checked in the browser.

`seeds.exs:1030` calls `Orders.cancel_order!` on a seeded online order. Cancelling now refunds through Stripe, and Stripe refuses the seed's fake PaymentIntent: "Stripe refused the refund, so nothing was cancelled." The seed should cancel these orders without a real Stripe call, still leaving the same states: Petra refunded in full, Oskar cancelled and not yet refunded.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 seeds.exs runs to the end on an empty database
- [ ] #2 The seeded orders end in the same states as before: Petra cancelled and refunded, Oskar cancelled with money to refund
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-22 20:13

---

Duplicate of TASK-97, which fixed the seed on main.

---
<!-- COMMENTS:END -->
