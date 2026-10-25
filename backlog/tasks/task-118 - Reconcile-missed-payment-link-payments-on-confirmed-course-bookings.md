---
id: TASK-118
title: Reconcile missed payment-link payments on confirmed course bookings
status: needs-triage
assignee: []
created_date: '2026-10-25 04:49'
labels:
  - spec
  - customers
  - admin
dependencies: []
references:
  - lib/edenflowers/courses/course_registration.ex
priority: high
type: bug
ordinal: 234000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A course booking that is already confirmed and pays its balance through its payment link gets that payment recorded even when the Stripe webhook never arrives.

**Why:** if the payment_intent.succeeded webhook is missed, the customer is charged but the payment is never recorded. Their link stays open, Jennie sees money still owed, and paying again fails with "payment temporarily unavailable".

## Problem

`CourseRegistration.record_link_payment` accepts a link payment on a `:confirmed` booking ("on one already confirmed it only records what arrived"). The `reconcile_payment` trigger, the safety net for missed webhooks, only selects `status in [:pending, :awaiting_payment]` (course_registration.ex:107), so a confirmed booking never gets reconciled. Orders do not have this gap: their trigger selects any order with a `payment_intent_id` (order.ex:317).

Retrying the link afterwards reuses the already-succeeded PaymentIntent, and Stripe rejects it with `payment_intent_unexpected_state`. The customer sees "Betalningen är tillfälligt otillgänglig".

## Repro (dev)

Without `just forward-stripe` running: confirm a booking, open its payment link (`Courses.open_registration_payment_link`), pay with 4242, wait two reconcile runs (10 min cron, 5 min grace). The booking still has its `payment_intent_id`, no Payment row is created, and paying the link again fails. Seen 2026-10-25 on registration 717740a1-14d0-4521-b8d7-921518e029de in dev.

## Open

- Does widening the trigger filter suffice, or does the `reconcile_payment` action itself assume an unconfirmed booking (it may call `confirm_payment`, whose `NotAlreadyConfirmed` validation would reject a confirmed one) and need to route confirmed bookings to `record_link_payment`?
- Should the payment link also recover by itself when its PaymentIntent has already succeeded, instead of showing the Stripe error?
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A confirmed booking whose link payment succeeded at Stripe without a webhook gets a Payment recorded by the next reconcile run
- [ ] #2 The payment link then shows the booking as paid, and the payment-received email is queued once
- [ ] #3 A test covers reconciling a link payment on a confirmed booking
<!-- AC:END -->
