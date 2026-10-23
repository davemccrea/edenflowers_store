---
id: TASK-105.5
title: Let Jennie send a payment reminder for an order or booking
status: ready-for-agent
assignee: []
created_date: '2026-10-23 18:42'
labels: []
dependencies:
  - TASK-105.2
parent_task_id: TASK-105
type: feature
ordinal: 218000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Chasing an unpaid link today means writing her own email, and the old bill email did it badly.

A menu item on the order and on the booking, shown while a balance is owed and not on invoice terms. It opens the message box and opens a payment link if none is open. Subject "A reminder about your order for <date>" / "A reminder about your booking on <course>". "A friendly reminder that <amount> is still to pay for your order for <date>.", Jennie's message, the totals block (bookings: course, date and amount), "You can pay online here:" and the link, then "If you've already paid, thank you, and please ignore this email." Sent by hand only, never automatically.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The menu item shows only while a balance is owed and the order isn't on invoice terms
- [ ] #2 Sending opens a payment link when none is open
- [ ] #3 Works for orders and course bookings
- [ ] #4 Previews on the admin Emails page cover every version, and the new copy is translated in en, fi and sv
<!-- AC:END -->
