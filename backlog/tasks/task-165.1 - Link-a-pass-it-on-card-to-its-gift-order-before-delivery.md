---
id: TASK-165.1
title: Link a pass-it-on card to its gift order before delivery
status: done
assignee: []
created_date: '2026-11-05 09:15'
updated_date: '2026-11-05 18:50'
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
- Jennie types the code printed on the card into the gift order's page (changed from scanning it and picking among today's deliveries, David 2026-11-05: starting from the order works whatever day she packs it). The field shows on gift orders only. No in-app scanner; add a camera only if typing proves annoying.
- One card per order. She can remove it and link another until the recipient first opens the card, in case she typed the wrong code.
- An admin opening the page never starts the code's 30 days (TASK-165.2).
- A linked card's page greets the recipient by first name (the order's recipient_first_name). Never the sender's name.
- A card she forgot to link works as usual, without a name.
- The order that used a card's code shows which gift order the card came with, and the gift order shows that its card brought in an order.
- Check whether the privacy page needs a line about showing the recipient's first name on the card's page.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Jennie links a card to a gift order by typing its code on the order's page
- [x] #2 A linked card's page greets the recipient by first name; an unlinked card's page has no name
- [x] #3 An order that used a card's code and the gift order it came with link to each other in admin
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-05: The 'Pass it on' page (prototype E) greets a linked card's recipient at the start of the message: 'Hej Anna! Någon tänkte på dig idag. Nu kan du göra samma sak för någon du tycker om.' An unlinked card keeps the line without the greeting.

Done 2026-11-05: Promotion.gift_order (one card per order) set by Jennie typing the card's code on a gift order's admin page; removable while gift_order_linkable? (no expiration_date yet). The page greets a linked card's recipient 'Hi Anna!'; the admin order pages link gift order and the order its card brought in.
Privacy page still to update (David words it himself): it tells recipients their details are used 'only to deliver, and never for marketing', but a linked card's page shows the recipient's first name to whoever holds the card, and we track whether the card brought in an order.

Privacy page follow-up is TASK-165.3.

2026-11-05 (David): linking and removing are Order actions (link_pass_it_on_card, remove_pass_it_on_card), logged in the order's History with the card's code, and only while the gift is still to deliver (pass_it_on_card_changeable?). Remove sits in the order's menu behind a confirmation. The section is headed 'Pass it on' (sv 'Skicka vidare', fi 'Anna eteenpäin'). The orders list's Show filter has 'Gift orders'.
<!-- SECTION:NOTES:END -->
