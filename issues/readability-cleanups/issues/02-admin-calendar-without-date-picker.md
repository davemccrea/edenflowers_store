# Render the admin calendar directly instead of through DatePicker

Status: needs-triage
Type: refactor

## Problem

`EdenflowersWeb.DatePicker` is the checkout date picker, configured by about ten callback assigns (`cell_state`, `cell_class`, `clickable_states`, `on_weekday_click`, `weekday_class`, `state_label`, `weekday_state_label`, …). `EdenflowersWeb.Admin.Calendar` wraps it and bridges those callbacks to the admin view, and `Admin.CalendarViewModel` combines several fulfilment options into one view with `:mixed` states.

## The idea

Depends on the single shop calendar (moving the calendar off `FulfillmentOption` onto one record; not yet written up as an issue). Once there's one calendar, the admin view only shows open/closed weekdays, per-date overrides, key dates and past days. Check whether rendering that directly (month grid, weekday headers, week toggles) reads simpler than configuring `DatePicker`. If it does, `DatePicker` loses the callbacks only admin uses.

## Comments

- Set to `ready-for-agent` once the shop calendar has landed, if the comparison favours it.
