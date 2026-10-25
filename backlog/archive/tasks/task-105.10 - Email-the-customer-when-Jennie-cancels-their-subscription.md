---
id: TASK-105.10
title: Email the customer when Jennie cancels their subscription
status: done
assignee: []
created_date: '2026-10-23 18:42'
updated_date: '2026-10-23 20:49'
labels: []
dependencies:
  - TASK-105.2
parent_task_id: TASK-105
type: feature
ordinal: 223000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Ending a recurring charge is something the customer should have in writing, and today Jennie's cancel says nothing.

The cancel action on the admin subscription page gets the tick box (ticked) and message box. "I've cancelled your <product> subscription. You won't be charged again.", Jennie's message, and, only when one exists, "Any delivery already charged will still come on <date>." An already-charged delivery is past the change deadline, so CancelOpenOccurrences leaves it in place.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Cancelling a subscription in the admin offers the email, ticked
- [x] #2 The email names an already-charged delivery that still comes
- [x] #3 Previews on the admin Emails page cover every version, and the new copy is translated in en, fi and sv
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The subscription log shows 'Cancellation emailed' but not the message: subscription versions have no message field, and the spec's log rule is for orders.
<!-- SECTION:NOTES:END -->
