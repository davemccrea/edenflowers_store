---
id: TASK-125
title: Prepare customer payments through an authoritative Ash operation
status: done
assignee: []
created_date: '2026-10-25 14:15'
updated_date: '2026-10-25 15:55'
labels:
  - spec
  - customers
  - developers
dependencies: []
references:
  - lib/edenflowers/payments.ex
  - lib/edenflowers/payments/validations/payable.ex
  - lib/edenflowers_web/features/checkout/checkout_live.ex
  - lib/edenflowers_web/payment_link.ex
  - lib/edenflowers_web/features/courses/course_live.ex
priority: high
type: refactor
ordinal: 247000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Customer checkout and Payment Link callers prepare payments through an Ash operation that owns eligibility, the amount and PaymentIntent setup.

**Why:** Today each web caller must remember its own eligibility checks and the update_amount/setup call sequence. One authoritative boundary prevents a new entry point from omitting rules or charging from stale page data.

Review evidence: CheckoutLive checks add-ons-only carts and stock before calling Payments.update_amount and Payments.setup. PaymentLink separately reloads and checks payment_link_open? and the shown balance before the same sequence. Payments is an Ash.Domain module, but these ordinary functions are not resource actions; the new-intent validation only checks payable?.

Put payment preparation behind specific resource action(s), exposing them through domain interfaces. Reload the authoritative record and enforce the rules applicable to that purchase before setting up payment. Keep presentation-specific confirmation of a changed displayed price in the UI if appropriate, but do not rely on it as the domain eligibility check. Reuse the Stripe adapter, existing setup functions and useful shared code; do not convert every integration helper into a resource or invent a payment service framework.

Received-money handling is separate: never move pre-payment cart rejection into payment-success handling, where money that already moved must be recorded. Preserve Payment Link access, saved-card ownership isolation, subscription behaviour and duplicate-payment protection.

Related: TASK-123 changes course checkout to revise in place and accept payment mismatches; this issue must not reintroduce exact-amount rejection at completion. Triage the smallest resource/action boundary and applicable eligibility rules before implementation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Store checkout, course checkout and Payment Link pages invoke domain payment-preparation actions rather than independently orchestrating amount updates and PaymentIntent setup.
- [x] #2 Direct action calls enforce applicable eligibility and authoritative pricing, including store add-ons-only and stock rules, without trusting preloaded page calculations.
- [x] #3 Guest/token-based payment access, signed-in saved-card isolation and subscription setup remain correct; existing integration code is reused rather than duplicated.
- [x] #4 Tests cover direct preparation with an ineligible/stale purchase, a valid retry and relevant actor/token access; succeeded payments remain recordable and TASK-123 mismatch semantics are preserved.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Generic actions: Order :prepare_checkout_payment (Orders.prepare_checkout_payment), CourseRegistration :prepare_checkout_payment (Courses.prepare_registration_checkout_payment), and Payable's :prepare_link_payment (Orders.prepare_order_link_payment / Courses.prepare_registration_link_payment), all over Payments.prepare/2 (update_amount, now private, then setup). Refusals are Payments.Errors.NotPayable with a reason. A course that filled or closed reopens the booking form on the course page with no flash, so no new copy is needed.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-25 15:44

---

Grilled. Decisions: (1) Order and CourseRegistration each get :prepare_checkout_payment; the Payable fragment gets :prepare_link_payment for both. (2) Store checkout enforces against the reloaded order: still a cart, not empty, not add-ons-only, no line over stock. Date/quote/promotion staleness out of scope. (3) Course checkout refuses unless pending without a payment link, booking still open and enough free places; confirmation stays lenient (TASK-123). (4) Link action enforces payment_link_open? and charges the reloaded balance; the shown-balance check stays in PaymentLink. (5) Checkout actor decides saved cards (guest nil); link preparation takes the token as its argument and never uses the visitor's saved cards. (6) Over-stock refusal is a typed error carrying the lines, rendered by CheckoutLive. (7) update_amount + setup merge into one function only the actions call.

---
<!-- COMMENTS:END -->
