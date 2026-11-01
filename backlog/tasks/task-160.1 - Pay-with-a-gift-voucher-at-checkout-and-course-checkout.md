---
id: TASK-160.1
title: Pay with a gift voucher at checkout and course checkout
status: ready-for-agent
assignee: []
created_date: '2026-11-01 17:32'
labels: []
dependencies: []
parent_task_id: TASK-160
type: feature
ordinal: 307000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Spending is what makes a voucher worth anything, and it needs the voucher model to exist first.

- Gift voucher resource (code, amount, expires_on, the order line that bought it), plus a 'what's left' calculation from its payments. A `:voucher` PaymentMethod and a voucher reference on Payment. 'Gift voucher' in CONTEXT.md.
- One 'pay from voucher' action on Payable: records min(what's left, Balance) as a `:voucher` payment. A purchase whose Balance reaches 0 is placed through the same path as a Stripe success.
- A 'Gift voucher' field in the payment step of checkout and course checkout, rate-limited (ash_rate_limiter). Shows the amount used and what's left. Works together with a promo code.
- Cancelling or refunding puts the voucher's part back as a negative `:voucher` payment.
- Expired or used-up vouchers are refused with a clear message.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A voucher pays part or all of an Online Order or course booking at checkout
- [ ] #2 A purchase fully paid by voucher is placed without Stripe
- [ ] #3 A cancelled or refunded purchase puts its voucher part back onto the voucher
- [ ] #4 Voucher lookups are rate-limited
<!-- AC:END -->
