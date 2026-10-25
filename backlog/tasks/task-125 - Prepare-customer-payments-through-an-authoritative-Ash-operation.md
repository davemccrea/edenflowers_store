---
id: TASK-125
title: Prepare customer payments through an authoritative Ash operation
status: needs-triage
assignee: []
created_date: '2026-10-25 14:15'
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
- [ ] #1 Store checkout, course checkout and Payment Link pages invoke domain payment-preparation actions rather than independently orchestrating amount updates and PaymentIntent setup.
- [ ] #2 Direct action calls enforce applicable eligibility and authoritative pricing, including store add-ons-only and stock rules, without trusting preloaded page calculations.
- [ ] #3 Guest/token-based payment access, signed-in saved-card isolation and subscription setup remain correct; existing integration code is reused rather than duplicated.
- [ ] #4 Tests cover direct preparation with an ineligible/stale purchase, a valid retry and relevant actor/token access; succeeded payments remain recordable and TASK-123 mismatch semantics are preserved.
<!-- AC:END -->
