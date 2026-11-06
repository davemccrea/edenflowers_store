---
id: TASK-181
title: >-
  Show why an admin email or button action failed, and keep the email drawer
  open with Jennie's edits
status: done
assignee: []
created_date: '2026-11-06 19:02'
updated_date: '2026-11-06 19:02'
labels:
  - admin
dependencies: []
priority: medium
type: bug
ordinal: 346000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The email drawer and the one-button admin actions tell Jennie what actually went wrong, the way TASK-180 did for the action drawers.

**Why:** On orders and course bookings a failed send closed the email drawer and threw away the email Jennie had rewritten, and several buttons flashed a guessed reason ("Choose a day after the current last day", "Could not remove the seat") that could be wrong.

The email drawer built a plain to_form(map) form and copied subject, body and To into each action by hand. It now uses an AshPhoenix form on each kind's own send action.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The email drawer builds its form with AshPhoenix.Form.for_update on the action that sends its kind
- [x] #2 A failed send keeps the drawer open with Jennie's edits, and a refused address shows on the To field
- [x] #3 The voucher's last-day form shows the action's refusal under the date
- [x] #4 Remove seat, payment link and undo payment flash the action's own reason
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
A send failure's own error is technical (Failed to send invoice: :no_stored_pdf), so the email drawer keeps each page's own failure flash and logs the error. Validation moved from the browser to Phoenix: the To field is a text input with the email keyboard, and the voucher form is novalidate. Course reminders and the invoice-draft and promotion deletes are unchanged: their messages match their only failures.
<!-- SECTION:NOTES:END -->
