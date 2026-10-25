---
id: TASK-19.4
title: Set same-day for every option with one bulk update
status: done
assignee: []
created_date: '2026-10-18 03:24'
updated_date: '2026-10-18 10:06'
labels:
  - quick
dependencies: []
parent_task_id: TASK-19
type: refactor
ordinal: 64000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** A hand-rolled transaction and loop does what one bulk update does.

### Problem

`Fulfillment.set_same_day_for_all/2` opens a transaction with `Ash.transact`, loops over every option calling `update_pricing`, and halts on the first error.

### What to build

- `Ash.bulk_update(FulfillmentOption, :update_pricing, changes, strategy: :atomic, return_records?: true, return_errors?: true)`, or the same through a code interface with `bulk_update`. `update_pricing` only sets attributes, so it runs as one statement, and the validations still apply.
- `FulfillmentsLive` reads the errors from the bulk result for the form, as it does now from the halted error.
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
set_same_day_for_all is one Ash.bulk_update (atomic by default). The existing FulfillmentsLive tests cover all-options, differing options and the rollback when a deadline is missing.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @david
created: 2026-10-18 03:24

---

- Moot if the single shop calendar lands first: same-day becomes one record's field. Do this only if that's not soon.

---
<!-- COMMENTS:END -->
