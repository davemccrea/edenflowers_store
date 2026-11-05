---
id: TASK-160.4
title: Let subscription orders draw from a gift voucher
status: done
assignee: []
created_date: '2026-11-01 17:32'
updated_date: '2026-11-05 18:50'
labels: []
dependencies:
  - TASK-160.1
parent_task_id: TASK-160
type: feature
ordinal: 310000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** TASK-162 sells gift subscriptions as vouchers, so a voucher has to keep paying after the first bouquet.

- A voucher used when a subscription starts is stored on the subscription. Checkout still saves a card.
- Each order the subscription creates draws from the voucher first (the same pay-from-voucher action), and the card is charged only for the rest. A fully covered order is placed without Stripe.
- The heads-up email shows how much the voucher covers.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Subscription orders are paid from the voucher before the card
- [x] #2 The card is charged once the voucher runs out or expires
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-05: A voucher entered on a subscription cart is kept on the Subscription. Each Occurrence carries it, so the card is charged only its stripe_amount, and an Occurrence the voucher covers is placed by place_paid_by_voucher without Stripe. A refused card still takes the voucher's part, and the payment link asks for the rest. Stripe only saves a card with a charge, so a voucher always leaves a subscription cart at least 0.50 € for the card (Order.saves_card?). The heads-up email says what the voucher pays. Its sv/fi lines are AI-drafted and queued as T28. Not covered: a retry after the voucher was spent elsewhere asks Stripe for a new amount under the same idempotency key and fails until a person steps in.
<!-- SECTION:NOTES:END -->
