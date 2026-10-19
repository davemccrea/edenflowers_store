---
id: TASK-50
title: Pick the card on a custom order as checkout does
status: in-progress
assignee: []
created_date: '2026-10-18 19:03'
updated_date: '2026-10-19 20:56'
labels:
  - spec
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 115000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie picks the card for a gift custom order from the same card choice as checkout, and the section asking who the flowers are for has a heading that matches its question.

**Why:** Today Jennie adds a card as an ordinary catalogue line. It is not marked as the order's card, so it shows as an item to make, stays on the order when she switches to "For me", and the card message length is not limited by the card's size. The "Recipient and card" heading also no longer fits a section that opens with "For me / For somebody else".

### What to build

- In `order_form_live.ex`, under "For somebody else", show the card choice from checkout's `gift_card_slot` (no card, or one of the card variants). Reuse checkout's components and wording.
- The chosen card becomes the order's card line (`is_card: true`), as `SwapCardLineItem` does at checkout. Choosing another card replaces it; choosing "For me" removes it, as `RemoveCardLineItem` does. Keep this in the `place_custom` and `edit` actions, not in the LiveView.
- The card message's length follows the chosen card's size (`ProductVariantSize.max_message_length/1`), as at checkout.
- A card line on the order is shown as the card, not as an item to make, on the order page and the Overview.

### Open questions

- **Heading:** "Who it's for" or "Gift", or something else. Ask Jennie.
- **Existing orders:** whether custom orders that already have a card added as a catalogue line should be marked as cards, or left as they are.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Jennie can pick a card for a gift custom order from the same choice as checkout
- [x] #2 The picked card is the order's card line, replaced when she picks another and removed when she switches to For me
- [x] #3 The card message is limited by the picked card's size
- [ ] #4 The section heading matches its For me / For somebody else question
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Built: `card_variant_id` argument on place_custom and edit; Changes.EnterCardLine adds it to the line_items argument (the order's own card kept by id at its sold price; any other card removed, as when not a gift). CardMessageLength limits the message to the chosen card's size. Checkout's card_drawer moved to EdenflowersWeb.CardDrawer and used by both forms. Cards are no longer offered as catalogue items on the form. The order page lists the card under Card to write, not To make. Existing orders with a card entered as a catalogue line are left as they are. The gift options now read The customer / Somebody else. Left open: AC #4, the section heading (still Recipient and card), waiting on Jennie.
<!-- SECTION:NOTES:END -->
