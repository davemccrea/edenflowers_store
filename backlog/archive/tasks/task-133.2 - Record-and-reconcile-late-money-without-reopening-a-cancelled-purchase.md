---
id: TASK-133.2
title: >-
  Record and reconcile late payments on retained cancelled orders and course
  bookings
status: done
assignee: []
created_date: '2026-10-25 22:24'
updated_date: '2026-10-26 05:03'
labels: []
dependencies:
  - TASK-133.1
references:
  - lib/edenflowers/payments.ex
  - lib/edenflowers/payments/changes/cancel_open_payment_intent.ex
  - lib/edenflowers/payments/changes/clear_paid_payment_intent.ex
  - lib/edenflowers/courses/course_registration/payment.ex
  - lib/edenflowers/orders/order/payment_link.ex
  - test/edenflowers/payments/reconcile_payment_test.exs
parent_task_id: TASK-133
type: bug
ordinal: 257000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Retaining purchases is only useful if the shared payment code can still resolve them and record real money after cancellation. A zero Balance describes the ledger now, not whether Stripe can send another successful payment.

Keep this small and shared. Reuse Payments.complete/1, RecordPayment, Payable, ReportAmountMismatch and current refund/reconciliation code. Normal website payment still places an order/confirms a pending registration using its saved details and actual amount. A payment on an already-confirmed manual Course booking reduces its Balance instead of confirming/consuming places again. A late payment on a cancelled record records money once, leaves the purchase cancelled and exposes a refund obligation; it must not reopen fulfillment, rebook places, reactivate subscriptions, emit normal booking confirmation or schedule attendance reminders.

Keep verified event/parent checks, actor access, unique Stripe IDs and transactional consistency. A legitimate actual payment must not be silently ignored merely because its parent was cancelled or its payment request changed. Preserve recoverable references to nonterminal intents if cancellation cannot succeed, and use conditional clearing so old cancellation cannot erase a replacement ID.

Reuse the current ten-minute reconciliation machinery and extend existing selection for cancelled parents with outstanding intents. Exercise scheduler/worker selection, not only a direct complete call. State the current older-than-five-minutes/newer-than-seven-days limits and existing manual developer recovery route honestly; no new Stripe-wide polling or scheduled refund scanner.

The revised parent has **no Invite or Archive workflow**. Do not add special withdrawn/archived states or filters. Recording a non-Stripe payment while a previously issued Stripe secret is still usable must preserve both actual money movements if both arrive, leaving any excess as a refund Balance. Do not implement new automatic refunds or a general locking framework.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Normal pending checkout keeps same-record actual-amount/mismatch handling; confirmed manual booking payments use existing Balance collection without duplicate place consumption or original booking confirmation.
- [x] #2 Late succeeded payments/refunds on cancelled order and course parents are recorded once and remain visible/refundable while the parent stays cancelled and unbooked/unfulfilled.
- [x] #3 Duplicate webhook/reconciliation delivery preserves exactly-once ledger effects and appropriate notifications; received money is not discarded because the purchase was cancelled.
- [x] #4 Nonterminal/failed cancellation preserves recoverable intent references; an old cancellation cannot clear a replacement. Closed/cancelled links reject new preparation without pretending old client secrets are instantly revoked.
- [x] #5 Existing scheduler/worker tests recover outstanding payments on cancelled parents inside the documented window; cadence, age limits and explicit manual recovery are documented.
- [x] #6 Focused tests cover offline collection plus late Stripe success on the same retained purchase, preserving both real payments and exposing any overpayment through existing Balance/refund controls.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Write narrow pending/confirmed/cancelled payment tests first. Extend current shared dispatch/terminal-state consequences rather than building course-only ingestion. Preserve nonterminal intent discoverability and conditional old-ID clearing. Test scheduler eligibility and duplicate/refund delivery. Keep network calls outside database transactions, no blanket row locks and no new Invite/Archive states.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Cancelled course payments now use ledger-only collection; cancelled order payments cannot restart subscriptions. Reconciliation includes cancelled parents within unchanged five-minute/seven-day updated_at window; manual recovery and limitations documented on Payments.reconcile/1. Cancellation retains intent until Stripe succeeds and atomically checks old ID before clearing; successful-payment clearing is conditional in SQL. Scheduler/worker tests cover both cancelled parents, duplicate success and refund; regression tests cover failed cancellation, replacement during cancellation, offline-plus-Stripe overpayment and cancelled occurrence subscription. Closed course link refuses new preparation. Focused payment/order/booking run: 279 tests passed. Confirmed booking and pending mismatch existing tests pass; restoring manual creation remains TASK-133.3.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-26 04:45

---

Revised to the final no-Invite/no-Archive model. Its role is shared payment safety for pending, confirmed/placed and cancelled purchases; manual-entry restoration is TASK-133.3.

---

author: @claude
created: 2026-10-26 04:46

---

Revised after the user removed both Invite and Archive workflows. This step now protects ordinary retained cancelled purchases and the shared Balance-payment semantics needed by confirmed-but-unpaid manual Course bookings. Supersedes references to withdrawn/archived states in earlier descriptions.

---
<!-- COMMENTS:END -->
