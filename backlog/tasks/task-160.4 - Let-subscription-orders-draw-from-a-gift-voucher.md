---
id: TASK-160.4
title: Let subscription orders draw from a gift voucher
status: ready-for-agent
assignee: []
created_date: '2026-11-01 17:32'
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
- [ ] #1 Subscription orders are paid from the voucher before the card
- [ ] #2 The card is charged once the voucher runs out or expires
<!-- AC:END -->
