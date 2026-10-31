---
id: TASK-155
title: Open the checkout calendar on the next month with a bookable date
status: done
assignee: []
created_date: '2026-10-31 10:24'
updated_date: '2026-10-31 10:26'
labels:
  - spec
  - customers
  - quick
dependencies: []
priority: medium
type: bug
ordinal: 290000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** On a month's last day after the same-day deadline (or whenever nothing in the current month is still open), checkout opens on a month where every date is disabled. The customer has to spot the small next-month chevron to find a date.

`StoreCalendar` passes only the selected date as `MonthGrid`'s `focus_date`, so a fresh checkout opens on today's month. Fix: fall back to `Availability.next_open_date/2` when no date is selected.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A checkout with no selected date opens on the month of the next open date
- [x] #2 With nothing open in the next 60 days, the calendar opens on the current month as before
<!-- AC:END -->
