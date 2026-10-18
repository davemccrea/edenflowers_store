---
id: TASK-29
title: Give the shop one calendar instead of one per fulfillment option
status: ready-for-human
assignee: []
created_date: '2026-10-18 14:27'
updated_date: '2026-10-18 15:06'
labels:
  - spec
  - admin
  - developers
dependencies: []
priority: medium
type: refactor
ordinal: 84000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The shop has one calendar of open days, shared by delivery and pickup, instead of one per fulfilment option

**Why:** Jennie is one florist. If she isn't working, nothing goes out, whichever way it reaches the Recipient. Today she keeps several calendars in step, and the code mostly exists to keep them in step for her.

### Problem

Each `FulfillmentOption` carries its own `available_days`, `enabled_dates`, `disabled_dates`, `same_day` and `order_deadline`. The admin already treats them as one calendar:

- The Fulfillments page opens on an "All options" calendar. `Admin.CalendarViewModel` (143 lines, 289 lines of tests) exists only to fold several options into one grid with `:mixed` cells, weekday headers and week toggles, and to decide which way a click should flip them.
- `FulfillmentsLive` writes every click to each scoped option (`apply_to_scope/2`, `replace_options/2`), and the option's own page repeats the calendar for that one option.
- Same-day moved to the same shape on 2026-10-17 (`set_same_day_for_all/2`, a bulk update across options plus a "varies" warning).
- Changing between delivery and pickup at checkout clears the chosen date, because the new option may have different open days.

### What to build

- `Edenflowers.Fulfillment.ShopCalendar`, a new single-row `shop_calendar` table holding `available_days`, `enabled_dates`, `disabled_dates`, `same_day` and `order_deadline`, with the `toggle_date`, `set_weekday`, `set_week` and `reset_calendar` actions and their changes moved over unchanged.
- `Availability.unavailable_reason/3` and the cell-state functions take the shop calendar. Callers stop reaching through the order's option: `Orders.Validations.FulfillmentDate`, `CreateOccurrence`, `SubscriptionDeliveryDay`, `SubscriptionManager`, the checkout and Custom Order date pickers, and the seeds.
- One calendar on the Fulfillments page. `CalendarViewModel`, the scope buttons, `apply_to_scope/2` and the per-option calendar on the edit page go.
- One same-day form saves to the shop calendar. `set_same_day_for_all/2`, the bulk-result error mapping, the "varies" warning and the same-day fields on each option's prices form go.
- The calendar and same-day fields leave `FulfillmentOption`, which keeps name, method and prices.

### What it simplifies

- `CalendarViewModel` and its tests are deleted. `:mixed` and `:all_past` disappear, and a weekday or week toggle flips one known state.
- `FulfillmentsLive` loses its scope assign and the fan-out of every edit across options.
- `set_same_day_for_all/2`, the bulk-result error mapping and the "varies" warning become one ordinary update form.
- The checkout date survives switching between delivery and pickup.
- Unblocks TASK-25: with one calendar, the admin grid may read simpler drawn directly than configured through `DatePicker`.

### Decisions

- **Delivery and pickup share every rule, same-day included.** @david: there is basically never a time when the options differ. No per-option exception.
- **Keeping per-option calendars and dropping the combined view was considered and rejected.** It removes a similar amount of code, but Jennie would have to close a day on every option, and forgetting one lets customers book a day she isn't working.
- **A new table, named for what it holds.** Nothing in the schema holds shop-wide settings yet. Keeping the columns on `fulfillment_options` and writing every row is the fan-out this removes. It isn't a general `shop_settings`; rename it if other shop-wide settings turn up.
- **The record is created on first use** (an upsert on a constant identity), open every day with same-day off. Migrations stay generated.
- **Today's settings are carried over by hand at deploy.** Before deploying, note the delivery option's open weekdays, future overrides and same-day cutoff. After deploying, set them on the shop calendar. There are only a few, so this is cheaper than a two-deploy data copy.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Jennie opens and closes days on one calendar, and checkout, Custom Orders and Subscriptions all book against it
- [x] #2 Admin.CalendarViewModel and the admin calendar scope are gone
- [x] #3 Switching between delivery and pickup at checkout keeps the chosen date when it is still open
- [x] #4 The Fulfillments page has one same-day form, and the option pages no longer have same-day fields
- [x] #5 FulfillmentOption no longer has available_days, enabled_dates, disabled_dates, same_day or order_deadline; they live on ShopCalendar in the shop_calendar table
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ShopCalendar is one row in shop_calendar. Fulfillment.get_shop_calendar!/1 runs the :get generic action, which reads first and only upserts when no row exists. An upsert on every read locked the row, which deadlocked async tests and would lock it on every checkout page. test_helper.exs commits the row before the sandbox starts; Generator.shop_calendar/1 sets it per test. Admin.Calendar.week_toggle_direction/3 replaces the CalendarViewModel week logic. Subscriptions take the account page's open weekdays (open_days).
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-18 14:39

---

From @david: there is basically never a time when the fulfillment options differ. Decided on one calendar with same-day included; open questions resolved. Deploy needs the manual carry-over in Decisions.

---

author: @claude
created: 2026-10-18 15:06

---

Code done; the full suite passes. What's left is the manual carry-over at deploy: before deploying, note the delivery option's open weekdays, future closed/opened dates and same-day cutoff. The migration drops those columns from fulfillment_options. After deploying, set them on the Fulfillments page calendar and same-day form.

---
<!-- COMMENTS:END -->
