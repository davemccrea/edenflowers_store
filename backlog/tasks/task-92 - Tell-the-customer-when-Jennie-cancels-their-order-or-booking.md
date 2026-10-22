---
id: TASK-92
title: Tell the customer when Jennie cancels their order or booking
status: ready-for-agent
assignee: []
created_date: '2026-10-22 14:39'
labels:
  - spec
  - customers
  - admin
dependencies: []
priority: high
type: feature
ordinal: 196000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie cancels an order or course booking in one step that refunds what she chooses and emails the customer, with an optional reason.

**Why:** When Jennie cancels, the customer hears nothing unless she remembers to tell them, and the refund is a separate step afterwards. Customers cancelling their own order already get a refund and an email.

### Decisions

1. **One cancel drawer for orders and bookings.** Cancel opens a side drawer (the pattern from TASK-79) with:
   - **Refund amount**: €0 up to what's held, starting at everything held. Hidden when nothing is held.
   - **Reason**: optional free text, stored as `cancellation_reason` and shown in the history. Jennie writes it in the customer's language.
   - **Email the customer**: ticked by default. When there's no customer email, the drawer says so and the cancel still goes through.
2. **Refunding and cancelling succeed or fail together.** The Stripe part is refunded before the transaction, as `RefundInFull` does. If Stripe refuses, nothing changes and nothing is emailed. Refund `amount_held - kept_amount` rather than the typed amount, so a retry never refunds twice.
3. **Whatever Jennie doesn't refund she keeps.** `kept_amount` moves into `Payments.Payable`, and a cancelled record's `total_due` is `kept_amount`, so its balance comes to 0. Money beyond what Stripe can refund is hers to hand back in person and record as today.
4. **Changing her mind later is a goodwill refund.** `set_refund` is deleted. `goodwill_refundable?` no longer excludes cancelled records.
5. **The email** is the standard cancelled text, then Jennie's reason as its own paragraph, then "I've refunded €X to your card" and/or "I'll return €Y". Queued through Oban in the cancel's transaction with the reason and amounts as args. BCC Jennie as now.
6. **The history** entry for a cancel shows the reason and whether the customer was emailed.
7. **No late-cancellation fee.** Jennie decides each late booking cancel herself. Customers are told: cancel by replying to the confirmation email, at least 7 days before for a full refund, after that get in touch.
8. **The customer's own order cancel is unchanged**: full refund, standard email, `kept_amount` 0.

Update `CONTEXT.md`: "Cancelled", "Total due" and the late-fee wording. Emailing on `remove_seat` is a separate spec.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Jennie can cancel an order or booking, refunding any amount up to what's held, in one step
- [ ] #2 The customer is emailed with the reason and what was refunded, unless Jennie unticks it
- [ ] #3 A refused Stripe refund leaves the record uncancelled and sends nothing
- [ ] #4 Courses have no late-cancellation fee
<!-- AC:END -->
