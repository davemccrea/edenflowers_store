---
id: TASK-60
title: Record course payments and refunds in a side drawer
status: done
assignee: []
created_date: '2026-10-19 06:44'
updated_date: '2026-10-20 18:53'
labels:
  - admin
  - spec
dependencies: []
priority: medium
type: feature
ordinal: 126000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie can record a course booking’s payment or refund in a focused side drawer without expanding or shifting the attendee list.

**Why:** Financial controls currently expand inside each booking row, moving the list and providing little booking or money context. A drawer makes it clearer whose money is being handled and distinguishes an actual Stripe refund from recording money already handed back.

## What to build

Replace the inline settlement panels in Admin.CoursesLive with one shared right-hand drawer for the selected booking. Keep the existing explicit “Record payment” and “Record refund” row buttons as entry points; do not make the whole row clickable.

Show the customer, course and date, plus the relevant paid amount, outstanding/refundable balance and retained cancellation fee. Render only the controls appropriate to that booking. Preserve existing payment methods, receipt selection, refund amount editing, eligibility rules, undo controls and shared PaymentActions behaviour. Clearly explain that “Refund with Stripe” moves money, whereas “Record refund” records money already returned outside Stripe.

Keep the drawer lean: no tabs, general booking editor, new payment features or changes to financial rules. On mobile it becomes full-screen. After success, close it, refresh the booking and restore focus sensibly; on errors keep it open with the entered values. Prevent duplicate submissions and accidental loss of edits.

## Tradeoff

Inline payment entry is compact and may be faster when settling several attendees consecutively. Keep the drawer flow quick and check that repeated recording remains practical.

## Implementation scope

Primary surface: lib/edenflowers_web/features/admin/courses_live.ex. Reuse existing drawer/dialog patterns where available and retain the shared payment handlers. Update courses LiveView tests for the new interaction; no backend redesign is intended.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Existing payment/refund buttons open a single drawer for the correct confirmed or cancelled booking without expanding attendee rows.
- [x] #2 Drawer identifies the customer, course and date and shows accurate relevant payment, balance and retained-fee context.
- [x] #3 Existing payment and refund behaviour is preserved, including methods, receipt choice, editable refund amount and Stripe eligibility; Stripe refunds and recording an outside-Stripe refund are clearly distinguished.
- [ ] #4 Successful submission closes the drawer and updates the list; errors preserve the open form and entered values; duplicate submissions and accidental loss of edits are guarded against.
- [ ] #5 Drawer supports keyboard focus containment, accessible labelling, close/Escape behaviour and focus restoration, and is full-screen on mobile.
- [ ] #6 LiveView tests cover opening the correct booking, payment/refund success and error behaviour, and continued availability of existing booking actions.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Drawer built in CoursesLive (settlement_drawer), opened by the row's Record payment/Record refund button via push_event js-exec, like order detail's fulfillment drawer. Closes on success; on error stays open with the message and the entered values. Goodwill Refund from the row menu stays inline (out of scope). Fixed SetRefund crashing on an invalid amount (it ran on an already-invalid changeset). Awaiting David's UI review before commit.

Also moved Add booking into its own drawer (#booking-drawer), laid out like order detail's fulfillment drawer: scrolling fields, footer with Add booking / Cancel. Menu Refund (goodwill) opens the settlement drawer in a goodwill mode. Drawer spacing aligned across store drawers (header pt-6 px-4 sm:pt-8 sm:pl-8, body p-4 sm:p-8) and admin drawers (88vw / 28rem, header/body p-4).
<!-- SECTION:NOTES:END -->
