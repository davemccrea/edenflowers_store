---
id: TASK-94
title: 'Refund a customer from one drawer, with or without cancelling'
status: done
assignee: []
created_date: '2026-10-22 15:59'
updated_date: '2026-10-22 17:56'
labels:
  - spec
  - customers
  - admin
dependencies:
  - TASK-92.2
priority: medium
type: feature
ordinal: 201000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie hands money back on any order or booking from one Refund drawer, and the customer is told.

**Why:** Refunding is three entry points today (Refund with Stripe, Record refund, and the menu's goodwill Refund), and Jennie has to know which applies. After TASK-92, Cancel is the only other way money goes back, so Refund can be one action.

### Decisions

1. **Two actions: Cancel and Refund.** Cancel (TASK-92) stops the order or booking. Refund hands money back and leaves it standing, or, on a cancelled record, gives back some of what Jennie kept.
2. **One drawer, shared with Cancel**, without the cancel part:
   - **Amount**: up to what's held. Starts at what's owed back if anything is, otherwise empty.
   - **Method**: Stripe for money paid through Stripe, otherwise how she hands it back. An amount covering both refunds through Stripe first, as Cancel does.
   - **Reason**: optional, stored with the refund and shown in the history.
   - **Email the customer**: ticked by default.
   It replaces Refund with Stripe, Record refund and the goodwill Refund. Record payment is unchanged.
3. **The domain splits the amount.** The part up to what's owed back (`-balance`) is an ordinary refund; the rest is recorded `goodwill`, as `SplitOffGoodwill` already does for dashboard refunds. Works on placed orders and confirmed or cancelled bookings, whatever the balance. `Validations.Recordable`'s refusal of refunds on a record that still stands goes, as far as the split makes it redundant.
4. **New emails** `order_refunded` and `booking_refunded`: how much, how it went back (card, MobilePay, or "I'll return") and the reason. BCC Jennie. Queued through Oban.
5. **"Goodwill" leaves the wording.** Admin copy and `CONTEXT.md` say Refund. In the glossary, goodwill is only the payment flag: the part of a refund beyond what was owed back. The monthly report is unchanged.

Copy through gettext; clear fuzzy msgstrs in en, fi and sv.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Order and booking pages have one Refund action opening the shared drawer; the three old refund entry points are gone
- [x] #2 A refund beyond what's owed back is split into ordinary and goodwill payments and leaves the record settled
- [x] #3 A refund works on standing and cancelled records, capped at what's held
- [x] #4 The customer gets a refunded email with amount, method and reason unless unticked
- [x] #5 No admin copy says goodwill
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
record_payment now takes money only; every refund goes through the refund action. A refund Jennie enters through Stripe no longer takes pending Stripe refunds off what it sends, since she names the amount; a cancel's refund still does.
<!-- SECTION:NOTES:END -->
