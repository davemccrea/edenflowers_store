# Check a fulfillment date with Availability directly

Status: ready-for-agent
Type: refactor

## Problem

`FulfillmentOption.fulfill_on_date` is a generic action with one caller, `Orders.Validations.FulfillmentDate`. `Actions.FulfillOnDate` loads the option by id, shifts `now` to Helsinki and calls `Availability.unavailable_reason/3`. Its comment says the action keeps the validator and calendar on one source of truth, but the calendars (`CheckoutLive`, `Admin.OrderFormLive`) already call `Availability` directly, which is that source.

## What to build

- `Validations.FulfillmentDate` loads the option with `Fulfillment.get_option_by_id/2` and calls `Availability.unavailable_reason(option, date, now)` with a Helsinki-zoned now (`ShopTime.now()` if `issues/readability-cleanups/issues/05-shop-time.md` has landed). A missing option keeps today's behaviour: no error from this validation, since `validate present(:fulfillment_option_id)` and `SnapshotFulfillmentMethod` already report it.
- Remove the `:fulfill_on_date` action, `Edenflowers.Fulfillment.Actions.FulfillOnDate`, and the `define :fulfill_on_date` code interface.
- `FulfillmentOption`'s `policy action_type(:action)` stays: `calculate_delivery` still needs it.
- `test/edenflowers/fulfillment/fulfillment_option_test.exs`, `describe "fulfill_on_date action"`: these cases are `Availability.unavailable_reason/3` cases with a database round trip. Move any not already covered in `availability_test.exs` there; delete the rest.

## Acceptance criteria

- [ ] `grep -r fulfill_on_date lib test` finds nothing
- [ ] The checkout `submit_delivery` date tests pass unchanged
- [ ] The existing suite passes

## Comments
