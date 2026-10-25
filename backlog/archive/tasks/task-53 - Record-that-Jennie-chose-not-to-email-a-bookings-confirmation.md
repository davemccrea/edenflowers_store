---
id: TASK-53
title: Record that Jennie chose not to email a booking's confirmation
status: done
assignee: []
created_date: '2026-10-18 19:39'
updated_date: '2026-10-18 19:44'
labels:
  - spec
  - developers
  - quick
dependencies: []
priority: low
type: refactor
ordinal: 119000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A booking Jennie adds without emailing the customer says so in its own field, instead of pretending its confirmation was sent.

**Why:** TASK-35 (commit 73448ceb) marks a booking as if its confirmation had been sent when Jennie unticks "Email the booking confirmation to the customer", so the every-10-minutes job that sends missed confirmations skips it. That makes the sent-confirmation record lie, and whoever reads it next will trust it.

Add a field on CourseRegistration recording that no confirmation email should be sent (generate the migration with `mix ash.codegen`). The add-booking action sets it from the checkbox, the confirmation change and the catch-up job skip bookings with it set, and the sent-confirmation record is only ever set when an email actually went out.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Unticking the email box sets the new field and leaves the sent-confirmation record empty
- [x] #2 Neither the add-booking action nor the catch-up job emails a booking with the field set
- [x] #3 Existing bookings and the ticked path behave as before
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
New skip_confirmation_email boolean on CourseRegistration (default false). add_manually sets it when the email box is unticked; the trigger's where and SendConfirmationEmail skip it. record_link_payment clears it so an online payment still sends the receipt, as before.
<!-- SECTION:NOTES:END -->
