---
id: TASK-20
title: Remove machinery the shop doesn't use
status: ready-for-agent
assignee: []
created_date: '2026-10-18 03:31'
updated_date: '2026-10-18 05:48'
labels: []
dependencies: []
ordinal: 67000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Remove machinery the shop doesn't use, so there's less to read and keep working

Each ticket is a deletion with no behaviour change for Jennie or customers. They're independent.

### Considered and kept

- `ash_archival` on `ProductVariant`: past orders reference removed sizes.
- The OTP rate limiter, maintenance mode, ErrorTracker with its log handler and alert emails, Typst receipts, web push for new orders, the free-delivery rules.

### Still to decide (not ticketed)

- Keeping key dates as they were when a weekday is toggled (`SetWeekday.preserve_key_dates_on_weekday/3`, the key-date skip in `SetWeek` and `CalendarViewModel`): drop if Jennie has never relied on it.
- AshAdmin at `/admin/ash`: it exposes default actions that bypass the narrowed ones (e.g. `FulfillmentOption`'s default `update` can change the method and rate type that `update_pricing` protects). Remove, or restrict to staging.
<!-- SECTION:DESCRIPTION:END -->
