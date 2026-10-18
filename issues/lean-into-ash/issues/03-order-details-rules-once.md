# Write the order-details rules once for place_custom and edit

Status: ready-for-agent
Type: refactor

## Problem

`Order.place_custom` and `Order.edit` repeat the same block of about 15 validations and changes for what Jennie enters (`order.ex`, lines 430 to 449 and 622 to 642): locale, customer name, email or phone, email format, `SnapshotFulfillmentMethod`, fulfillment option and date, `FulfillmentDateNotPast`, `DeliveryAddress`, recipient phone for delivery, card message length, phone normalising, `SetGiftFromRecipient`, `PriceFulfillment`. A rule added to one and not the other goes unnoticed.

## What to build

- Move the shared block into the resource-level `validations do` and `changes do` sections, each scoped with `where: [action_is([:place_custom, :edit])]`.
- Leave in each action only what differs: `place_custom`'s state, origin, reference, payment link and email; `edit`'s placed/pending checks, `user_id` reset and stock.

## Watch out for

- Order. The block interleaves changes and validations: `SnapshotFulfillmentMethod` must run before `validate present(:recipient_phone_number), where: [attribute_equals(:fulfillment_method, :delivery)]`. Check how Ash orders global changes and validations against the action's own before relying on it. If the order can't be kept, put the block in one `Changes.OrderDetails` change module instead, which runs its steps in sequence. That's less idiomatic but keeps both actions in step.
- `@custom_order_fields` already shares the accepted attributes; keep it.

## Tests

- The existing `place_custom` and `edit` tests pass unchanged.

## Acceptance criteria

- [ ] Each rule in the block appears once in `order.ex`
- [ ] The existing suite passes

## Comments
