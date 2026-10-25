---
id: TASK-11.6
title: Show the report building and download it faster
status: done
assignee: []
created_date: '2026-10-19 08:56'
updated_date: '2026-10-19 20:30'
labels:
  - quick
dependencies: []
parent_task_id: TASK-11
type: feature
ordinal: 132000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** the monthly report takes a while to download and the Export drawer gives no sign it is working, so Jennie cannot tell if a click did anything and may click again.

Two causes: `MonthlyReport.build/2` fetches each receipt from Papra one after another, and the drawer is a plain `GET` form, so the page cannot know when the zip is ready.

What to build:
- Fetch receipts with `Task.async_stream(..., max_concurrency: 5, timeout: :infinity)`. Req's own `receive_timeout` bounds each request, and a failure still lands on the existing missing-receipt path. The Stripe call stays sequential.
- Download starts the build with `start_async` in `ExpensesLive`. While it runs the button is disabled and the drawer shows "Building report…" (no per-receipt count). Closing the drawer does not stop it; leaving the page abandons it.
- When it finishes, `push_event` sends the zip (base64) and filename to a colocated hook that saves it as a file. Mark the size ceiling with a `ponytail:` comment: if months get big enough to choke the socket, move to a temp file behind a signed one-time route.
- Missing receipts: red flash, put by the LiveView directly. Build failure: red flash and the button is enabled again.
- Delete `AccountingController`, its `/admin/accounting` route, the PubSub broadcast and the `admin:accounting` subscription.
- The drawer's Download button becomes `variant="primary"` (brand green). The header Export button stays neutral.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Receipts are fetched from Papra up to 5 at a time
- [x] #2 Clicking Download disables the button and shows "Building report…" in the drawer until the zip is ready or the build fails
- [ ] #3 The finished zip downloads as redovisning-YYYY-MM.zip without leaving the expenses page
- [x] #4 Missing receipts and a failed build each show a red flash; after a failure Download can be clicked again
- [x] #5 AccountingController, its route and the admin:accounting PubSub messages are gone
- [x] #6 The drawer's Download button is brand green (variant primary); the header Export button stays neutral
- [x] #7 expenses_live_test covers the download, missing receipts and build failure through the LiveView
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Receipts fetched via Task.async_stream (5 at a time). ExpensesLive builds the report with start_async and push_events the base64 zip; a phx:download window listener in app.js (matching the other phx: listeners there, so no hook) turns it into a Blob download. AccountingController, its route and the PubSub messages are deleted.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-19 09:00

---

Left for a human: click Download on /admin/expenses in a real browser and check the zip saves (AC #3). The push and its contents are covered by tests; the browser side of the download is not.

---

author: @claude
created: 2026-10-19 13:44

---

Download path replaced by TASK-11.7: a GET to ReportController from Overview instead of start_async and a pushed zip, so AC #3 no longer applies. The parallel Papra fetch stays.

---

author: @claude
created: 2026-10-19 20:30

---

#3 was overtaken by 9d6598fb: the report now downloads from the Overview through ReportController, as redovisning-YYYY-MM.zip (report_controller_test). Left unticked because the expenses-page download it describes is gone.

---
<!-- COMMENTS:END -->
