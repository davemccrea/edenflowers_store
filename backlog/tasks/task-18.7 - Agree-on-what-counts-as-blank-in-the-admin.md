---
id: TASK-18.7
title: Agree on what counts as blank in the admin
status: done
assignee: []
created_date: '2026-10-18 03:12'
updated_date: '2026-10-18 07:21'
labels:
  - quick
dependencies: []
parent_task_id: TASK-18
type: refactor
ordinal: 58000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

Three admin LiveViews each define a private `present?/1`, and they disagree:

- `Admin.OrderFormLive`: `is_binary(value) and String.trim(value) != ""`, so whitespace is blank.
- `Admin.OrderDetailLive`: `nil` and `""` are blank, anything else is present, so `"  "` is present. Its `presence/1` builds on it.
- `Admin.DashboardLive`: `nil` is blank, otherwise `String.trim(value) != ""`, which raises on a non-string.

So an order whose Card Message is only whitespace gets an empty card widget on the order page but no card badge on the dashboard.

### What to build

- One helper, available to every admin LiveView (e.g. in `EdenflowersWeb.Admin.Components`, or a small `EdenflowersWeb.Blank` module), with the order form's meaning: only a string with non-whitespace content is present. Keep `presence/1` beside it if `OrderDetailLive` still needs it.
- Remove the three private copies.
- Better still where it applies: trim on the way in (`constraints: [trim?: true]` on the attribute), so the stored value is never whitespace-only and the views only check for `nil`. Decide per field; don't change stored data in this ticket.

### Tests

- The existing suite passes. Add a LiveView test that a whitespace-only Card Message doesn't render the card widget on the order page.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 One definition of `present?/1` in the web layer
- [x] #2 The existing suite passes
<!-- AC:END -->
