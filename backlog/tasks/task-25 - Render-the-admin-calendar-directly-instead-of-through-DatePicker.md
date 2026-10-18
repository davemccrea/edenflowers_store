---
id: TASK-25
title: Render the admin calendar directly instead of through DatePicker
status: needs-triage
assignee: []
created_date: '2026-10-18 11:35'
updated_date: '2026-10-18 11:37'
labels:
  - spec
  - developers
dependencies: []
priority: low
type: refactor
ordinal: 80000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The admin calendar draws its own month grid, so DatePicker drops the callbacks only the admin uses

**Why:** Once there's one shop calendar, configuring `DatePicker` through admin-only callbacks may be harder to follow than drawing the calendar directly.

### Problem

`EdenflowersWeb.DatePicker` is the checkout date picker, configured by about ten callback assigns (`cell_state`, `cell_class`, `clickable_states`, `on_weekday_click`, `weekday_class`, `state_label`, `weekday_state_label`, …). `EdenflowersWeb.Admin.Calendar` wraps it and bridges those callbacks to the admin view, and `Admin.CalendarViewModel` combines several fulfilment options into one view with `:mixed` states.

### The idea

Depends on the single shop calendar (moving the calendar off `FulfillmentOption` onto one record; not yet written up as an issue). Once there's one calendar, the admin view only shows open/closed weekdays, per-date overrides, key dates and past days. Check whether rendering that directly (month grid, weekday headers, week toggles) reads simpler than configuring `DatePicker`. If it does, `DatePicker` loses the callbacks only admin uses.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-18 11:35

---

From @david on TASK-18.2: set to `ready-for-agent` once the shop calendar has landed, if the comparison favours it.

---
<!-- COMMENTS:END -->
