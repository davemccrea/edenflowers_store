---
id: TASK-128
title: Derive refund-method choices and defaults from the shared payment domain
status: done
assignee: []
created_date: '2026-10-25 14:15'
updated_date: '2026-10-25 21:45'
labels:
  - spec
  - admin
  - developers
dependencies: []
references:
  - lib/edenflowers/payments/payable.ex
  - lib/edenflowers/payments/validations/refundable.ex
  - lib/edenflowers_web/features/admin/components/components.ex
  - lib/edenflowers_web/features/admin/order_detail_live.ex
priority: medium
type: refactor
ordinal: 250000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Refund forms, previews and actions use the same domain facts to decide which payment methods can return money and which method is the default.

**Why:** The component and order preview currently repeat method-selection decisions that the refund validation separately enforces. Keeping these together prevents the UI offering a method the action rejects or previewing a different default.

Review evidence: Admin.Components.refund_method_options and default_refund_method decide from paid_through_stripe/paid_outside_stripe. OrderDetailLive repeats the default selection for its preview. Payments.Validations.Refundable separately limits refunds by method and remaining money.

Put unformatted method eligibility/default facts on Payments.Payable through calculations and have both the validation and the form/preview consume the same rules. Preserve the per-method amount limits and all financial validation. Labels, translated confirmations and form layout stay in the web layer; do not create a generic policy framework.

This complements TASK-121's capability centralisation but can ship independently. Triage the exact default/choice behaviour for mixed-method and zero-held-money records before implementation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Orders and course registrations expose shared refund-method eligibility and default-method facts from Payments.Payable; form and preview no longer duplicate those decisions.
- [x] #2 The refund action validates method eligibility and remaining per-method amounts against the same domain rules, including mixed Stripe/non-Stripe money.
- [x] #3 Translated labels and form rendering remain in the web layer; cancellation/refund accounting and existing customer-email behaviour are unchanged.
- [x] #4 Tests cover Stripe-only, non-Stripe-only, mixed and exhausted funds, and verify that displayed defaults/choices agree with domain eligibility.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Triage (2026-10-25): Stripe money held -> default Stripe (mixed too). No Stripe held -> default the non-Stripe method holding the most, Zettle on none. Nothing held -> no methods, no default; action rejects. Non-Stripe stays one pot: every non-Stripe method offered once outside-Stripe money is held.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-25 21:45

---

Architecture-review follow-up, grilled and approved: the shared Refund drawer now provides the effective default-plus-entered values to both form and preview, including legacy cash-paid Course bookings. Reopening retains the entered values and matching preview. Refund eligibility/default calculations and financial validation remain in Payable.

---
<!-- COMMENTS:END -->
