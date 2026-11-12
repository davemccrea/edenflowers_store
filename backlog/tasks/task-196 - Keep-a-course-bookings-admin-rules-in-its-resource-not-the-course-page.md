---
id: TASK-196
title: 'Keep a course booking''s admin rules in its resource, not the course page'
status: done
assignee: []
created_date: '2026-11-12 17:17'
updated_date: '2026-11-12 17:24'
labels:
  - spec
  - developers
  - quick
dependencies: []
references:
  - lib/edenflowers_web/features/admin/course_detail_live.ex
  - lib/edenflowers/courses/course_registration.ex
  - lib/edenflowers/courses/course_registration/admin.ex
  - lib/edenflowers/courses/course.ex
  - lib/edenflowers/courses.ex
  - lib/edenflowers/payments/payable.ex
  - lib/edenflowers/orders/order.ex
  - lib/edenflowers/orders/order/admin.ex
  - test/edenflowers_web/features/admin/course_detail_live_test.exs
  - docs/agents/ash-liveview-review.md
  - docs/agents/testing.md
  - docs/adr/0007-elixir-calculations-for-unqueried-money-booleans.md
priority: low
type: refactor
ordinal: 361000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The admin course page reads what a Course booking is and allows from the booking resource, the way the order page reads an order.

**Why:** To know what Jennie can do with a booking you have to read the course page's template and load list, while for an order you read the resource. The page also has its own `paid?` that means something different from the resource's `paid?`, and `remove_seat` would take a seat off a cancelled booking if anything called it.

## Problem

`lib/edenflowers_web/features/admin/course_detail_live.ex` holds four things that belong to the booking:

- **The load list.** `load_course/2` (lines 517-537) passes 15 booking fields to `Courses.get_course_by_id`. The Order keeps the same kind of list inside `read :admin_show` (`lib/edenflowers/orders/order/admin.ex`).
- **The seat rule.** The menu offers Remove a seat on `@registration.seats_held > 1` (line 617). The `remove_seat` action (`course_registration/admin.ex`) checks only that more than one seat is left, not that the booking is confirmed.
- **A second `paid?`.** `defp paid?(registration), do: Decimal.positive?(registration.amount_paid)` (line 718) picks the Remove a seat confirmation's wording. The resource's `paid?` (`course_registration.ex:296`) means nothing is left to pay.
- **Where the PaymentIntent id lives.** `stripe_payment_intent_id/1` (lines 667-668): the first Payment's id, or the booking's own while a payment is pending.

## Decisions (grilled 2026-11-12)

- The fix is small. No `admin_menu_actions` calculation for bookings: the menu has six items and four already read one calculation each (`to_collect?`, `refundable?`, `undoable?`).
- No new money status shared by orders and bookings. `payment_status`, `to_collect?` and `to_refund?` stay as they are.
- The grouping into confirmed, cancelled still to settle and cancelled settled stays in the page. Every booking is shown, so it is grouping for display, and it already reads `cancelled_unsettled?`.
- `seat_removable?` means confirmed and holding more than one seat. `remove_seat` refuses anything else.
- The Remove a seat warning is about money to hand back, so it reads `holds_money?` (money still with the shop), not net amount paid.
- The booking's `payment_reminder?` is left alone. It is always true for a confirmed booking, so the drawer's payment link wording never shows for one. That changes what Jennie sees, so it is not part of this move.

## What to build

1. A Course read action for the admin course page, in the style of the Order's `admin_show`, that loads the bookings with everything the page and its drawers need, with a code interface on `Edenflowers.Courses`. The page stops passing a load list.
2. A `seat_removable?` calculation on the booking: `status == :confirmed and seats_held > 1`. The menu reads it. `remove_seat` validates against it and keeps its atomic guard against two removals at once.
3. Move `holds_money?` from `Order` (`order.ex:994`) to the `Payable` fragment, so bookings have it. Delete the page's `paid?` and use `holds_money?` for the confirmation wording.
4. A `stripe_payment_intent_id` calculation on the booking, computed in Elixir from its loaded payments. Delete the page's helper.
5. Drop the `@registration.status == :confirmed` check in the menu (line 575). The menu is only rendered for confirmed bookings, so it is always true.

## Behaviour change

After a Goodwill refund of everything a booking paid, the Remove a seat confirmation stops warning "This does not refund. Refund the seat here afterwards", because no money is held.

## Tests

Follow `docs/agents/testing.md`: the rules at the Ash level, the page tests for wiring only. Touch existing course page tests only where the move breaks them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The course page gets a course and its bookings from a Course read action and passes no load list of booking fields
- [x] #2 seat_removable? is true only for a confirmed booking holding more than one seat, tested at the Ash level for confirmed, one seat left and cancelled
- [x] #3 remove_seat refuses a cancelled booking and a booking's last seat, tested at the Ash level
- [x] #4 holds_money? is defined once on the Payable fragment and works for orders and bookings; the course page has no paid? of its own
- [x] #5 stripe_payment_intent_id on a booking gives its Payment's PaymentIntent, or the booking's own while a payment is pending, tested at the Ash level
- [x] #6 The course page's menu offers the same items for a confirmed booking as before, and the existing course page tests pass
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
remove_seat has two validations so each refusal keeps its own wording: `is not confirmed` for a cancelled booking, then Holds on seat_removable? (only_when_valid?) with the existing last-seat message. The atomic guard stays for two removals at once.

holds_money? has no test of its own on a booking: it is one expression over amount_held (testing.md: don't test a calculation mirroring its expression). The changed Remove a seat confirmation wording after a full Goodwill refund has no page test.
<!-- SECTION:NOTES:END -->
