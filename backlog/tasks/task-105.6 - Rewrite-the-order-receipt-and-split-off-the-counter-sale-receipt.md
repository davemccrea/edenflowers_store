---
id: TASK-105.6
title: Rewrite the order receipt and split off the counter-sale receipt
status: ready-for-agent
assignee: []
created_date: '2026-10-23 18:42'
labels: []
dependencies: []
parent_task_id: TASK-105
type: feature
ordinal: 219000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The receipt is the first contact with an online customer, and a counter sale reached its wording by hiding two lines.

Order receipt (online checkout only): subject "Your Eden Flowers order for <date>", thanks, when and where, the items and total in the body as well as the PDF, "For <recipient>" and the card message for gifts, and the cancel-until line while the order can be cancelled.

Counter-sale receipt: subject "Your receipt from Eden Flowers", "Thank you for your purchase. Your receipt is attached.", items and total. Sent automatically when the customer gave an email, no tick box. Says nothing about flowers, since the sale may be a vase.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Online checkout sends the order receipt with items, total and gift details in the body
- [ ] #2 A counter sale sends the counter-sale receipt
- [ ] #3 Previews on the admin Emails page cover every version, and the new copy is translated in en, fi and sv
<!-- AC:END -->
