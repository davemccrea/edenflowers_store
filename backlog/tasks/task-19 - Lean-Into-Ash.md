---
id: TASK-19
title: Lean Into Ash
status: needs-triage
assignee: []
created_date: '2026-10-18 03:24'
labels: []
dependencies: []
ordinal: 60000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Close a concurrency gap on cancelling and editing orders, and let Ash do work the code does by hand

### What's already right

Kept here so later work keeps the same idioms:

- `ProductVariant.adjust_stock` updates stock atomically, and `AdjustStock` sorts its locks so two orders can't deadlock.
- `CourseRegistration.remove_seat` is a fully atomic update, its error raised inside the expression.
- `CreateOccurrence` puts `Ash.Changeset.filter(state == :active)` on the update, so a pause made while the card is charged wins, and moves the date with `atomic_update`.
- `finalize_checkout` transitions with `always_atomic?: true`; identities on `payment_intent_id`, `stripe_refund_id` and `reverses_payment_id` stop duplicate payment rows.
- `User.ensure_stripe_customer` uses `get_and_lock_for_update()`; `Token.expunge_expired` uses `change filter`.
- `ReserveSeats` locks the course row and counts seats from an aggregate. That's the right tool there, since the count can't be one atomic expression.

### The gap

`Order.cancel`, `cancel_by_customer` and `edit` are not atomic, so their state checks read the record passed in rather than the row. The admin order page cancels the order it loaded on mount. Ticket 01.

### Leaning further in

| Ticket | Ash feature | Replaces |
|---|---|---|
| 02 | `manage_relationship` + AshPhoenix nested forms | `ReplaceLineItems` and `EnteredLineItems` diffing the order's lines by hand |
| 03 | Resource-level `validations` and `changes` with `where: action_is(...)` | The block repeated in `:place_custom` and `:edit` |
| 04 | `Ash.bulk_update` | `Fulfillment.set_same_day_for_all/2` looping over options in a hand-rolled transaction |
| 05 | Read actions with arguments, relationship sorts | Domain rules built inline in admin LiveViews |
| 06 | — | `AdjustStock` locking a row only to log an oversell |

The email check (`TASK-18.6`) is now an `Ash.Type.NewType` too.

### Out of scope

- Making `ToggleDate`, `SetWeekday` and `SetWeek` atomic with SQL array functions. One admin edits the calendar, and the single shop calendar will rewrite them anyway.
- The search callbacks in `ExpensesLive`, `CustomersLive`, `ProductsLive`, `PromotionsLive` and `SubscriptionsLive`: Cinder hands them a query and expects one back.
- Swapping every bare `Ash.get`/`Ash.update`/`Ash.destroy` in the admin for a code interface. They pass the actor, so policies apply; convert them when touching a file.
<!-- SECTION:DESCRIPTION:END -->
