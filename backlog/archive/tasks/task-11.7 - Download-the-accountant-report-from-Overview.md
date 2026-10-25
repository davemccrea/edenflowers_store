---
id: TASK-11.7
title: Download the accountant report from Overview
status: done
assignee: []
created_date: '2026-10-19 13:44'
updated_date: '2026-10-19 13:52'
labels:
  - quick
dependencies: []
parent_task_id: TASK-11
type: refactor
ordinal: 134000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** the report covers income as well as expenses, so it belongs next to the month's sales on Overview, and the start_async build that pushed a base64 zip over the socket was more code than the download needs.

What to build:
- Overview gets an "Accountant report" card under "This month": an `<input type="month">` defaulting to last month and a Download button, in a plain GET form with `target="_blank"`. The new tab loads while the zip builds and closes once the download starts.
- `ReportController` at `/admin/reports?month=YYYY-MM` builds the zip and sends it with `send_download/3`. A failed build or malformed month redirects to Overview with an error flash. Non-admins get a 404.
- Delete the Export drawer, `start_async`/`handle_async` and the `phx:download` listener from Expenses and `app.js`.
- A download can't carry a flash, so `MonthlyReport.build/2` stops returning the missing-receipt count. A missing receipt's row still says so in the spreadsheet.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Overview has an Accountant report card defaulting to last month
- [x] #2 Download saves redovisning-YYYY-MM.zip through ReportController
- [x] #3 A failed build or malformed month redirects to Overview with an error flash
- [x] #4 The Expenses Export drawer and the phx:download listener are gone
- [x] #5 report_controller_test covers the download, the failures and the admin check
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-19 13:44

---

Left for a human: click Download on /admin in a real browser and check the new tab closes and the zip saves. The response and its contents are covered by tests; the browser side is not.

---

author: @claude
created: 2026-10-19 13:52

---

Verified by the user on 2026-10-19: Download on the Overview's Accountant report card saved the zip.

---
<!-- COMMENTS:END -->
