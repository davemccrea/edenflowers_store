---
id: TASK-13.3
title: Show one balance panel on orders and bookings
status: done
assignee: []
created_date: '2026-10-17 16:35'
updated_date: '2026-10-19 20:30'
labels: []
dependencies:
  - TASK-13.2
parent_task_id: TASK-13
type: refactor
ordinal: 37000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### What to build

Decision 5 of the spec.

- A `balance_panel` component in the admin components, taking a record that includes `Payable` and its payments: "To collect" or "To refund" with the amount; "Refund with Stripe" when `stripe_refundable?`; the record-a-payment-or-refund form prefilled with the balance, or with `outside_stripe_refund` for a refund. A slot for extra actions. Rendered only when the record isn't `settled?`.
- The order page uses it, with its payment link buttons in the slot. It loses `owes_money?`, `refundable_outside_stripe?`, the `refund_outside_stripe` component, the refund branch of `payment_form/1`, and `paid_through_stripe?` where it decides refunds (the "Fetch refunds from Stripe" menu item may keep it).
- The courses page uses it for each booking that isn't settled. It loses `refundable_outside_stripe?`, `refundable_with_stripe?`, `stripe_paid/1`, `outside_stripe_refund/1` and its hand-built refund forms. The quick "Record payment" on a booking row stays where it is, as the florist taps it at the course.
- "Refund with Stripe" calls `Payments.refund_balance/1` on either record, as both pages do today.
- Copy stays in the admin's payment vocabulary (commit 053a1ecb): "To collect", "To refund", "Record a payment", "Record a refund", "Refund with Stripe".

### Tests

LiveView tests, each run on the order page and the courses page:

- To collect: the panel shows the amount and a payment form prefilled with it; recording it settles the record and the panel goes.
- To refund, paid by card and cash: both "Refund with Stripe" and the refund form show, the form prefilled with the cash share.
- Settled: no panel.
- A cancelled order paid by card shows "To refund" and "Refund with Stripe", the gap this spec started from.
- Recording a refund from the panel, prefilled, settles a cancelled record paid in cash.
- "Refund with Stripe" on a cancelled record paid by card refunds through the Stripe mock and settles it.
- A refused amount shows the validation message and records nothing.
- The order page's payment link buttons show only while something is to collect.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Both pages render the same panel, and neither LiveView computes balance, settled or refund limits itself
- [ ] #2 Every case above passes on both pages
- [x] #3 gettext extracted and merged, with fuzzy msgstrs cleared in en, fi and sv
- [x] #4 The existing suite passes
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-19 20:30

---

#1 and #2 were overtaken by TASK-13.5 and TASK-17.3: the courses page now has its own compact settlement controls on each row, and only the order page renders balance_panel. Left unticked because they no longer describe the code.

---
<!-- COMMENTS:END -->
