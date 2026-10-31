---
id: TASK-151
title: Fix the checkout calendar test that fails on a month's last day
status: needs-triage
assignee: []
created_date: '2026-10-31T09:45:00Z'
updated_date: '2026-10-31T09:45:00Z'
labels:
  - spec
  - developers
  - quick
dependencies: []
priority: low
type: bug
ordinal: 287000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** CI goes red on the last day of every month on every branch, so a real failure can hide behind it and PRs look broken when they are not.

"An open checkout sees dates close and reopen without a reload" in `test/edenflowers_web/features/checkout/checkout_delivery_live_test.exs` closes `ShopTime.today() + 1` and expects its day button to turn `aria-disabled`. The checkout calendar (`MonthGrid`, `month_grid.ex:125`) only renders day buttons for the month on screen, and opens on the current month. On a month's last day tomorrow has no button: the first `refute` passes vacuously and the `assert` after closing the date fails. Seen on PR #311 (31 October 2026).

Proposed fix (tried in the closed PR #312, never run): when tomorrow is in next month, click `#calendar-next-month` before the assertions, and assert the day button exists before refuting `aria-disabled`, so the test cannot pass vacuously again.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The test fails if the day button it checks is missing, rather than passing vacuously
- [ ] #2 The test passes on the last day of a month as well as on any other day
<!-- AC:END -->
