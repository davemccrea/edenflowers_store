---
id: TASK-11.5
title: Open the accountant export in a drawer
status: done
assignee: []
created_date: '2026-10-18 19:31'
updated_date: '2026-10-18 19:34'
labels: []
dependencies: []
parent_task_id: TASK-11
type: feature
ordinal: 118000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** the month picker and download button sit loose in the expenses page header, which crowds it, especially on a phone. An Export button that opens a drawer gives the export one place to grow if it ever needs more options.

Replace the month picker and "Download for the accountant" button on the admin expenses page with one "Export" button. It opens the existing `<.drawer>` component (core_components.ex, already used for the admin nav), which holds the month picker (defaults to last month) and the download button. Submitting still hits `GET /admin/accounting?month=YYYY-MM`. Only the month for now; no other options until one is needed.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The expenses page header shows one Export button instead of the month picker and download button
- [x] #2 Export opens a drawer with the month picker, defaulting to last month, and a download button that downloads that month's zip
- [x] #3 The drawer works at phone width and closes with Escape and its close button
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Export button opens a right-hand <.drawer> (#export-drawer) holding the month picker and Download button; the form still GETs /admin/accounting. Checked at 375px in the running app: opens, closes with Escape and the close button.
<!-- SECTION:NOTES:END -->
