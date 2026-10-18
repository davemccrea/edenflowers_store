---
id: TASK-52
title: >-
  Reword the left-at-door delivery email so it doesn't suggest the flowers might
  be lost
status: ready-for-agent
assignee: []
created_date: '2026-10-18 19:21'
updated_date: '2026-10-18 19:22'
labels:
  - spec
  - customers
  - quick
dependencies: []
priority: low
type: task
ordinal: 117000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The email a customer gets when their flowers are left because nobody was home (order_left_at_door) has a cleaner closing line and reads right for gift orders.

**Why:** "If you can't find them, just reply and I'll help." puts the idea in the customer's head that their flowers might be missing, when the photo already shows exactly where they are. And on a gift order the email goes to the buyer, but it says "Nobody was home" and "I left them" as if the buyer was the one receiving them.

Today the template (lib/edenflowers/email/templates/order_left_at_door.text.eex) says "Nobody was home when I delivered your flowers, so I left them in the spot shown in the attached photo." and closes with "Thank you for your order. If you can't find them, just reply and I'll help."

- Replace the closing with the one order_delivered.text.eex uses: "Thank you for your order. If anything isn't as it should be, just reply and I'll take care of it." Reusing that msgid means fi/sv already have it translated.
- On a gift order, name the recipient the way order_delivered.text.eex does (branch on @order.recipient_first_name, e.g. "Your flowers for %{recipient} were delivered while nobody was home...").
- Update the en/fi/sv translations to match.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The left-at-door email no longer says "If you can't find them" or anything suggesting the flowers might be lost
- [ ] #2 The closing still thanks the customer and reads naturally in English, Finnish and Swedish
- [ ] #3 The email works for gift orders too: it names the recipient, as the normal delivered email does
<!-- AC:END -->
