---
id: TASK-105.3
title: Split Order updated from Order details and drop the bill
status: done
assignee: []
created_date: '2026-10-23 18:42'
updated_date: '2026-10-23 20:06'
labels: []
dependencies:
  - TASK-105.2
parent_task_id: TASK-105
type: feature
ordinal: 216000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** "Here is what we agreed" and "I've updated your order" are different news, and the bill version mixed a late first send with a payment reminder.

Order details: subject with the date, "Thank you for your order. Here is what we agreed:", the totals block, delivery or pickup line, "For <recipient>" and the card message for gifts, then the payment-terms line ("You can pay online here:" with the link / "I'll send you an invoice after delivery" / "You pay on delivery", pickup wording to match). Ticked by default when placing.

Order updated: subject "Your updated Eden Flowers order for <date>", "I've updated your order.", Jennie's message, the order as it now stands, the payment line only if something is owed, "If anything doesn't look right, just reply." Offered with a tick box, unticked by default, when Jennie saves an edit. No line promising to refund a credit.

The bill version and its `order_details_state` switch go. Sending details for a handed-over order shows them without the delivery line.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Placing a custom order sends Order details with the agreed wording when ticked
- [x] #2 Saving an edit offers Order updated, unticked by default
- [x] #3 No email reads "I hope you're happy with it. Here are the details"
- [x] #4 Previews on the admin Emails page cover every version, and the new copy is translated in en, fi and sv
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The refused-card version of Order details became Subscription payment failed here (TASK-105.9's wording), since the state switch had to go. Order updated shares the totals, fulfillment and payment partials with Order details.
<!-- SECTION:NOTES:END -->
