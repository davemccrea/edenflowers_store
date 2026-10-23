---
id: TASK-107
title: Remind course bookers the day before
status: ready-for-agent
assignee: []
created_date: '2026-10-23 18:42'
labels:
  - spec
  - customers
dependencies: []
priority: medium
type: feature
ordinal: 229000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Everyone booked on a course gets an email the day before with when and where it is.

**Why:** Courses are often booked weeks ahead, and a forgotten place is a lost seat and a disappointed customer.

Decided in the email grilling session on 2026-10-23. Automatic, Jennie's voice, signed by her, no tick box. Subject "See you tomorrow at <course>". "A reminder that <course> is tomorrow.", when and where, "See you there". No what-to-bring line: the website has it. A booking still awaiting payment gets it too, with the amount still to pay and "You can pay online here:" with its link. Sent once, by a queued job (ADR 0005).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Confirmed and awaiting-payment bookings get the reminder the day before the course
- [ ] #2 An awaiting-payment booking's reminder includes the amount and payment link
- [ ] #3 Cancelled bookings and released holds get nothing
- [ ] #4 Previews on the admin Emails page cover every version, and the new copy is translated in en, fi and sv
<!-- AC:END -->
