---
id: TASK-120
title: Book a course place only once it is paid
status: ready-for-agent
assignee: []
created_date: '2026-10-25 10:08'
labels:
  - spec
  - customers
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 239000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A course place counts as booked only once its payment has arrived; before that a registration is a checkout in progress or an invite Jennie sent.

**Why:** Unpaid bookings holding places make the seat counts, the emails and their copy branch on 'booked but not paid'. Paid-only booking leaves one meaning of booked, for Jennie and for customers.

Decisions (grilled 2026-10-25):
- States: pending -> confirmed -> cancelled, declared with AshStateMachine. :awaiting_payment goes; any left in production are cancelled first.
- No checkout hold. Places are counted from confirmed bookings only. :register still refuses a closed or already-full course, but a payment that arrives when the course has filled meanwhile is confirmed anyway; Jennie makes room.
- Jennie's 'Add booking' creates a pending invite with a payment link and holds no places. Paying it confirms it, even past the limit.
- Unpaid rows are deleted, never cancelled: a nightly job purges online checkouts left pending for a day, and withdrawing an invite deletes it. Cancelled only ever means a paid booking called off.
- Invites show in their own 'Invited, not paid yet' section on the admin course page, with resend and withdraw. Not counted in places, not on the Overview's money to collect.
- Status name stays :pending (no data migration).
- Emails: confirmation always comes with the receipt; the reminder goes to confirmed bookings only; the invite email carries the payment link.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CourseRegistration status is an AshStateMachine with pending, confirmed and cancelled
- [ ] #2 Seat counts (seats_taken, seats_booked, booking_open?) count confirmed bookings only
- [ ] #3 Add booking creates a pending invite that holds no places; paying it confirms it
- [ ] #4 Abandoned pending checkouts are purged after a day; withdrawing an invite deletes it
- [ ] #5 The admin course page lists invites separately from bookings
- [ ] #6 Course emails no longer branch on an unpaid booking; mix print_emails reviewed in sv, fi and en
<!-- AC:END -->
