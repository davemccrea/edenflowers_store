---
id: TASK-123
title: >-
  Let customers revise course checkout in place and flag payment mismatches like
  store orders
status: needs-triage
assignee: []
created_date: '2026-10-25 14:12'
labels:
  - spec
  - customers
  - admin
  - developers
dependencies: []
references:
  - lib/edenflowers_web/features/checkout/checkout_live.ex
  - lib/edenflowers_web/features/courses/course_live.ex
  - lib/edenflowers/courses/course_registration.ex
  - lib/edenflowers/payments.ex
priority: medium
type: refactor
ordinal: 245000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Customers can go back and correct an unpaid course checkout without deleting its registration; a payment that completes during an edit confirms the booking and leaves any difference for Jennie to settle, as store checkout does.

**Why:** The discard-and-recreate flow makes a small correction depend on safely deleting a record that Stripe may still need. Reusing the registration and accepting occasional payment mismatches is simpler for this single-florist store than cancellation/replacement orchestration or blocking customers from going back.

## Agreed decision

- Follow the existing store checkout pattern: keep the same registration, reopen a prefilled name/email/places form, save revisions through an Ash resource action, and bring the existing PaymentIntent amount up to date before another payment attempt. Reuse existing Payments behaviour rather than cancel and replace an intent merely because details changed.
- Replace course checkout confirmation's exact-amount rejection with the store's record-and-report approach. A succeeded payment is recorded and the pending registration is confirmed even when the amount differs from its current price. Preserve duplicate-webhook protection and queue the normal confirmation only once.
- The confirmed booking uses the registration's saved details and number of places when confirmation wins. If revision wins first, confirmation uses the revised registration. If confirmation wins first, a stale revision must not change the confirmed booking. Enforce this in Ash/the database, not just the page.
- Accepted trade-off: starting an EUR 85 payment for one place and saving two places at EUR 170 before it completes can produce a confirmed two-place booking with EUR 85 still to collect. The reverse leaves money to refund. Jennie resolves these occasional differences manually. Do not reject received money or automatically undo the customer's revision to preserve exact payment matching.
- Use the existing Payment ledger, Balance calculations, admin settlement/attention views, and the store's mismatch-reporting pattern. No new payment framework, persisted recovery state, automatic refund, or retry loop.
- Customers still cannot edit or cancel confirmed course bookings themselves; they contact Jennie. Existing admin cancellation/refund behaviour remains.

## Scope and relationship to the WIP

TASK-122 / commit 663b67ea safeguards deletion while Stripe finishes a payment. This decision replaces discard/recreate specifically for customer checkout editing. A failed-payment return must preserve a retryable checkout rather than delete it or display an indefinite confirmation message for a failed attempt. Do not blindly revert the WIP: abandoned-checkout cleanup, invite withdrawal, and Custom Order deletion still need their existing payment-safety guards.

Reuse the store checkout and shared payments code, but inspect the course-specific confirmation action and validators rather than assuming they already tolerate mismatches. Update CONTEXT.md and relevant payment/course ADR documentation to record the accepted confirmed-but-underpaid booking semantics.

## Triage note

The product decision above was explicitly agreed in conversation. This ticket remains needs-triage under the repository convention because the grilling skill was not run; do not treat that status as reopening the accepted mismatch trade-off.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Going back during unpaid checkout preserves and prefills name, email and places; continuing revises the same registration ID without deleting/recreating it or cancelling its PaymentIntent just to edit details.
- [ ] #2 Revision validation, pricing, customer association and pending-only mutation rules live in Ash actions/changes. A stale revision cannot modify a registration that has been confirmed meanwhile.
- [ ] #3 A subsequent payment attempt updates/reuses the PaymentIntent through existing shared payment behaviour; a failed attempt remains retryable without creating a second registration or falsely claiming payment is being confirmed.
- [ ] #4 A succeeded payment confirms the pending registration even when underpaid or overpaid, records the actual amount once, reports the mismatch using the existing store pattern, and queues confirmation once. Duplicate webhook/reconciliation delivery cannot duplicate money or booking confirmation.
- [ ] #5 The accepted EUR 85 one-place payment versus revised EUR 170 two-place booking confirms two places and exposes EUR 85 to collect through existing admin settlement/attention views; the reverse exposes the excess to refund without automatically refunding it.
- [ ] #6 Regression tests cover ordinary back/edit/retry, failed-payment returns, both revision-versus-confirmation orderings, underpayment, overpayment and duplicate completion. Deletion safeguards for cleanup, invite withdrawal and Custom Orders remain covered; precommit passes.
- [ ] #7 Domain documentation records the mismatch trade-off and confirms that customer editing/cancellation of confirmed bookings remains unavailable.
<!-- AC:END -->
