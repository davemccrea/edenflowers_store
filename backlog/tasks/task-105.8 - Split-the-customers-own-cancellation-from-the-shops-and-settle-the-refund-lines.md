---
id: TASK-105.8
title: >-
  Split the customer's own cancellation from the shop's, and settle the refund
  lines
status: ready-for-agent
assignee: []
created_date: '2026-10-23 18:42'
labels: []
dependencies:
  - TASK-105.2
parent_task_id: TASK-105
type: feature
ordinal: 221000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** A customer who cancelled in their account wants a plain confirmation; a cancellation by the shop is news that may need Jennie's explanation.

Cancellation confirmed (customer cancelled in their account): matter-of-fact, no greeting, signed Eden Flowers, from the automated address. Subject "Order #<ref> cancelled". The cancellation, "Refund: <amount> to Visa •••• 4242", "Refunds usually take 3–5 working days to appear on your statement.", "Questions? Reply to this email." Jennie's copy still reaches her inbox.

Order cancelled (by the shop): neutral, no built-in apology. "Your order for <date> is cancelled.", Jennie's message, the refund and to-return lines, "If you have any questions, just reply to this email." Ticked by default; message optional.

Order refunded: the refund line first, then Jennie's message. Ticked for card and MobilePay refunds, unticked for cash. Booking cancelled and Booking refunded follow the same order of lines.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A customer cancelling in their account gets the matter-of-fact confirmation
- [ ] #2 A shop cancellation and every refund email put the fact first and Jennie's message after it
- [ ] #3 Card refund lines say how long the money takes; cash reads "I've refunded <amount> in cash"
- [ ] #4 The refund tick box is unticked for cash
- [ ] #5 Previews on the admin Emails page cover every version, and the new copy is translated in en, fi and sv
<!-- AC:END -->
