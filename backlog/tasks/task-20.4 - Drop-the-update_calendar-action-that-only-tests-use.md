---
id: TASK-20.4
title: Drop the update_calendar action that only tests use
status: ready-for-agent
assignee: []
created_date: '2026-10-18 06:37'
labels:
  - quick
dependencies: []
parent_task_id: TASK-20
type: refactor
ordinal: 77000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

`FulfillmentOption.update_calendar` (and its `Fulfillment.update_calendar` code interface) has no caller in the app. The admin calendar edits through `toggle_date`, `set_weekday`, `set_week` and `reset_calendar`. Only two tests use it, to set up disabled dates: `order_test.exs` ("save_step_3 rejects a date the option no longer allows") and `fulfillments_live_test.exs`.

### What to build

- Set those tests' calendars up another way: pass `disabled_dates` to the `fulfillment_option` generator, or use `toggle_date`.
- Remove the `:update_calendar` action and its `define`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `grep -rn update_calendar lib test` finds only DatePicker's unrelated `update_calendar_view`
- [ ] #2 The existing suite passes
<!-- AC:END -->
