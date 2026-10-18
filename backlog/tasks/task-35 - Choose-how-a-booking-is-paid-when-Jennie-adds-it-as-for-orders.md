---
id: TASK-35
title: 'Choose how a booking is paid when Jennie adds it, as for orders'
status: done
assignee: []
created_date: '2026-10-18 18:22'
updated_date: '2026-10-18 19:38'
labels:
  - spec
  - admin
  - customers
dependencies: []
priority: medium
type: feature
ordinal: 93000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Choosing how the customer pays should mean the same thing everywhere. On a custom order Jennie picks "Send a payment link" or "Record the payment later"; when she adds a course booking she can't choose, and has to send a link from the row menu afterwards.

Give the Add booking form on the courses page the same payment radio and "Email the customer" checkbox as the custom order form (ticked by default). Send a payment link: open the link on the booking and put it in the confirmation email, as the order-details email does. Record later: as today. Unticked: add the booking without emailing. Reuse the order form's components and wording.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Add booking offers Send a payment link and Record the payment later, worded as on the order form
- [x] #2 With a payment link and email ticked, the confirmation email carries the link
- [x] #3 With email unticked, no email is sent
- [x] #4 Record later behaves as Add booking does today
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
add_manually takes payment_link? (default false) and email_customer? (default true); the form defaults to a payment link with email ticked, as the order form does. The confirmation email carries the open link and sets payment_link_emailed_at, so the row menu offers Resend. Unticked marks confirmation_emailed_at so the trigger's 10-minute scheduler doesn't send it anyway.
<!-- SECTION:NOTES:END -->
