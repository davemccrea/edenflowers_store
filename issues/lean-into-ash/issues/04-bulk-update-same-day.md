# Set same-day for every option with one bulk update

Status: needs-triage
Type: refactor

## Problem

`Fulfillment.set_same_day_for_all/2` opens a transaction with `Ash.transact`, loops over every option calling `update_pricing`, and halts on the first error.

## What to build

- `Ash.bulk_update(FulfillmentOption, :update_pricing, changes, strategy: :atomic, return_records?: true, return_errors?: true)`, or the same through a code interface with `bulk_update`. `update_pricing` only sets attributes, so it runs as one statement, and the validations still apply.
- `FulfillmentsLive` reads the errors from the bulk result for the form, as it does now from the halted error.

## Comments

- Moot if the single shop calendar lands first: same-day becomes one record's field. Do this only if that's not soon.
