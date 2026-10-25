---
id: TASK-120
title: Book a course place only once it is paid
status: done
assignee: []
created_date: '2026-10-25 10:08'
updated_date: '2026-10-25 10:43'
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
- [x] #1 CourseRegistration status is an AshStateMachine with pending, confirmed and cancelled
- [x] #2 Seat counts (seats_taken, seats_booked, booking_open?) count confirmed bookings only
- [x] #3 Add booking creates a pending invite that holds no places; paying it confirms it
- [x] #4 Abandoned pending checkouts are purged after a day; withdrawing an invite deletes it
- [x] #5 The admin course page lists invites separately from bookings
- [x] #6 Course emails no longer branch on an unpaid booking; mix print_emails reviewed in sv, fi and en
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented 2026-10-25. Seat count is one aggregate, seats_booked (confirmed only). Invite payment goes through :confirm_payment (confirmation + receipt); :record_link_payment is now only a balance on a confirmed booking. Pending rows are deleted by :discard (course page 'Change booking', failed MobilePay, admin 'Withdraw invite', nightly discard_abandoned for checkouts without a link). ReserveSeats became PriceBooking (no row lock). New sv/fi msgstrs for the invite email and admin invite section need Jennie's review. BEFORE DEPLOY: check production for course_registrations with status awaiting_payment and cancel them, or reading them will fail.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-25 10:43

---

Before deploying: run just backup, then check prod for awaiting_payment registrations (none expected) and cancel any. sv/fi copy for the new invite strings is drafted, not yet reviewed by Jennie.

---
<!-- COMMENTS:END -->
