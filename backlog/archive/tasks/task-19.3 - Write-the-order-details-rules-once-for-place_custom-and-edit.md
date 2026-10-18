---
id: TASK-19.3
title: Write the order-details rules once for place_custom and edit
status: done
assignee: []
created_date: '2026-10-18 03:24'
updated_date: '2026-10-18 10:05'
labels:
  - wontfix
dependencies: []
parent_task_id: TASK-19
type: refactor
ordinal: 63000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** `place_custom` and `edit` repeat the same rules, so a rule added to one and not the other goes unnoticed.

### Problem

`Order.place_custom` and `Order.edit` repeat the same block of about 15 validations and changes for what Jennie enters (`order.ex`, lines 430 to 449 and 622 to 642): locale, customer name, email or phone, email format, `SnapshotFulfillmentMethod`, fulfillment option and date, `FulfillmentDateNotPast`, `DeliveryAddress`, recipient phone for delivery, card message length, phone normalising, `SetGiftFromRecipient`, `PriceFulfillment`. A rule added to one and not the other goes unnoticed.

### What to build

- Move the shared block into the resource-level `validations do` and `changes do` sections, each scoped with `where: [action_is([:place_custom, :edit])]`.
- Leave in each action only what differs: `place_custom`'s state, origin, reference, payment link and email; `edit`'s placed/pending checks, `user_id` reset and stock.

### Watch out for

- Order. The block interleaves changes and validations: `SnapshotFulfillmentMethod` must run before `validate present(:recipient_phone_number), where: [attribute_equals(:fulfillment_method, :delivery)]`. Check how Ash orders global changes and validations against the action's own before relying on it. If the order can't be kept, put the block in one `Changes.OrderDetails` change module instead, which runs its steps in sequence. That's less idiomatic but keeps both actions in step.
- `@custom_order_fields` already shares the accepted attributes; keep it.

### Tests

- The existing `place_custom` and `edit` tests pass unchanged.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each rule in the block appears once in `order.ex`
- [ ] #2 The existing suite passes
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-18 10:05

---

Tried resource-level validations and changes with where: action_is([:place_custom, :edit]). Ash still runs atomic/3 on every global change and validation for every other update, even when the where clause excludes it, so mark_fulfilled, return_to_* and the rest stopped being atomic (67 failures with the changes, compile warnings with the validations alone). A macro or a hand-run change module costs more than 15 repeated lines, so each action now carries a comment saying to change both.

---
<!-- COMMENTS:END -->
