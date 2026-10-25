---
id: TASK-118
title: Reconcile missed payment-link payments on confirmed course bookings
status: done
assignee: []
created_date: '2026-10-25 04:49'
updated_date: '2026-10-25 06:20'
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
A confirmed course booking gets its payment-link payment recorded by the existing reconciliation job when its Stripe webhook is missed.

**Why:** a customer can be charged while the booking still shows money owed. Reconciliation must recover this payment without asking them to pay again.

## Problem

The course reconciliation trigger selected only pending and awaiting_payment bookings. A confirmed booking with an outstanding payment-link PaymentIntent was excluded, even though the shared payment completion code already supports recording that payment.

Reproduced in dev without `just forward-stripe`: pay the balance on a confirmed booking through its payment link, then wait for reconciliation. The PaymentIntent remained on the booking, no Payment row was recorded, and retrying payment failed because the intent had already succeeded. No production incident was established.

## Agreed scope

- Include confirmed bookings in the existing course reconciliation trigger.
- Reuse Payments.complete and its existing record_link_payment routing; add no new job or payment-handling path.
- Keep the 10-minute schedule, 5-minute webhook grace period, and 7-day updated_at cutoff. Cancelled bookings remain excluded.
- Test scheduler eligibility, recovery of the remaining balance, closing the payment link, preserving confirmation, and duplicate payment/email protection when the webhook arrives later.
- Immediate recovery on the payment-link page is out of scope.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A confirmed booking whose link payment succeeded at Stripe without a webhook gets a Payment recorded by the next reconcile run
- [x] #2 The payment link then shows the booking as paid, and the payment-received email is queued once
- [x] #3 A test covers reconciling a link payment on a confirmed booking
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Add a failing scheduler-to-worker regression for a confirmed booking link payment, including late webhook deduplication. 2. Include confirmed bookings in the existing trigger filter; preserve timing and other statuses. 3. Run focused and broader tests, and update acceptance criteria.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Regression failed before the fix because the course scheduler queued no worker for the confirmed booking. Added :confirmed to the existing trigger filter; shared payment completion needed no change. Added recovery and scheduler-exclusion tests. Validation: focused suite 7/7, full suite 1507/1507 (seed 734222), formatting and strict Credo pass. Initial full-suite run had one photo-gallery assertion failure; its 22-test file and the full suite both passed on rerun with the same seed. No production access or deployment.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @agent
created: 2026-10-25 06:15

---

Scope agreed with the user: extend the existing course reconciliation job to include confirmed bookings with an outstanding PaymentIntent. Keep the 10-minute schedule, 5-minute grace period and 7-day cutoff. Shared Payments.complete already routes confirmed bookings to record_link_payment. Cover scheduler eligibility, recording the payment, closing the payment link and duplicate payment/email protection. Immediate recovery on the payment-link page is explicitly out of scope. Reproduction was in dev without Stripe forwarding; no production incident has been established.

---
<!-- COMMENTS:END -->
