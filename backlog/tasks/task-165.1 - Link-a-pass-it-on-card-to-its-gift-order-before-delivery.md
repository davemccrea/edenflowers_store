---
id: TASK-165.1
title: Link a pass-it-on card to its gift order before delivery
status: ready-for-agent
assignee: []
created_date: '2026-11-05 09:15'
updated_date: '2026-11-05 16:14'
labels: []
dependencies: []
parent_task_id: TASK-165
type: feature
ordinal: 337000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Knowing which gift a card went out with lets the 'Pass it on' page greet the recipient by name and shows which gifts bring in new customers.

Decisions (grilled 2026-11-05):
- Jennie scans the card's QR with her phone's normal camera. Signed in as admin, the 'Pass it on' page shows her today's gift deliveries instead of the customer view, and she taps the matching order. No in-app scanner.
- One card per order. She can re-pick until the recipient first opens the card, in case she tapped the wrong order.
- An admin opening the page never starts the code's 30 days (TASK-165.2).
- A linked card's page greets the recipient by first name (the order's recipient_first_name). Never the sender's name.
- A card she forgot to link works as usual, without a name.
- The order that used a card's code shows which gift order the card came with, and the gift order shows that its card brought in an order.
- Check whether the privacy page needs a line about showing the recipient's first name on the card's page.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Scanning a card while signed in as admin lets Jennie link it to one of today's gift deliveries
- [ ] #2 A linked card's page greets the recipient by first name; an unlinked card's page has no name
- [ ] #3 An order that used a card's code and the gift order it came with link to each other in admin
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-05: The 'Pass it on' page (prototype E) greets a linked card's recipient at the start of the message: 'Hej Anna! Någon tänkte på dig idag. Nu kan du göra samma sak för någon du tycker om.' An unlinked card keeps the line without the greeting.
<!-- SECTION:NOTES:END -->
