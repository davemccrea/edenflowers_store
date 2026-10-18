---
id: TASK-20.2
title: Check a fulfillment date with Availability directly
status: ready-for-agent
assignee: []
created_date: '2026-10-18 03:31'
updated_date: '2026-10-18 06:08'
labels:
  - quick
dependencies: []
parent_task_id: TASK-20
type: refactor
ordinal: 69000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

`FulfillmentOption.fulfill_on_date` is a generic action with one caller, `Orders.Validations.FulfillmentDate`. `Actions.FulfillOnDate` loads the option by id, shifts `now` to Helsinki and calls `Availability.unavailable_reason/3`. Its comment says the action keeps the validator and calendar on one source of truth, but the calendars (`CheckoutLive`, `Admin.OrderFormLive`) already call `Availability` directly, which is that source.

### What to build

- `Validations.FulfillmentDate` loads the option with `Fulfillment.get_option_by_id/2` and calls `Availability.unavailable_reason(option, date, now)` with a Helsinki-zoned now (`ShopTime.now()` if `TASK-18.5` has landed). For a missing option, return `:ok`: `SnapshotFulfillmentMethod` already reports "Invalid fulfillment option". Today the `case` in `check_availability/2` has no `{:error, _}` clause, so an unknown id raises `CaseClauseError` instead; add a test for it.
- Remove the `:fulfill_on_date` action, `Edenflowers.Fulfillment.Actions.FulfillOnDate`, and the `define :fulfill_on_date` code interface.
- `FulfillmentOption`'s `policy action_type(:action)` stays: `calculate_delivery` still needs it.
- `test/edenflowers/fulfillment/fulfillment_option_test.exs`, `describe "fulfill_on_date action"`: these cases are `Availability.unavailable_reason/3` cases with a database round trip. Move any not already covered in `availability_test.exs` there; delete the rest.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `grep -r fulfill_on_date lib test` finds nothing
- [ ] #2 The checkout `submit_delivery` date tests pass unchanged
- [ ] #3 The existing suite passes
<!-- AC:END -->
