---
id: TASK-162.3
title: Put a pass-it-on card in every gift delivery
status: ready-for-human
assignee: []
created_date: '2026-11-01 14:07'
updated_date: '2026-11-05 11:36'
labels: []
dependencies:
  - TASK-164
  - TASK-165
parent_task_id: TASK-162
type: task
ordinal: 300000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Every gift delivery reaches someone who was just given flowers, and most never learn where they came from. A card inviting them to pass the gift on, with their own discount, turns recipients into customers.

Decisions (grilled 2026-11-01):
- Every gift delivery (the order's gift badge in admin) gets a card, except funeral and sympathy orders: Jennie leaves those out. Pickups and non-gift deliveries don't get one.
- Each card has its own one-use code for 15% off, no end date, for anyone and any order. The 'pass it on' framing is the message, not a rule.
- Cards are bilingual (sv, fi), 85x55 mm, double-sided. The first batch is about 100. Codes and print-ready PDF come from TASK-165. Their QR codes open the shop with the card's code on the cart (TASK-164); the code is also printed for typing.
- Results show in Umami under source card, campaign pass-it-on, and as uses of the batch's codes.

Rollout:
1. Jennie approves or rewrites the card text (draft in TASK-165).
2. David runs the batch and sends the PDF.
3. Print on thick paper (about 300 g), double-sided, and cut.
4. Jennie scans each card to link it to its order (TASK-165.1), then tucks it into the gift delivery.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Jennie has approved the card text
- [ ] #2 The first batch is printed and cut
- [ ] #3 Cards go into gift deliveries, except funerals
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-05: Jennie's approval (step 1) also covers the 'Pass it on' page copy (/sv/skicka-vidare).
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-01 16:15

---

Grilling (2026-11-01): David's idea is a 'pass it on' card. The recipient of a delivered gift finds a card with a QR code, a short message inviting them to pass the gift on to someone else, and a one-use code for 15% off. Decided:
- Deliveries only.
- Codes come from a batch of unique one-use Promotions, each printed on its own card (variable-data printing). No receipt printer and no per-order code.
- No end date printed. A code works until used or until Jennie retires the batch.
- Anyone can use it on any order. The 'pass it on' framing is the message, not a rule.
Facts: there is no printer integration in the app. Promotions already support one-use codes (usage_limit). A code can't be applied from a URL today; it has to be typed at checkout.

---

author: @claude
created: 2026-11-01 16:19

---

Grilling continued (2026-11-01):
- Cards are generated with Typst, like receipts. A batch per language, starting with 50 Finnish and 50 Swedish. Each card has its own one-use 15% code.
- Batches are made by a mix task or rpc that David runs for now. An admin button can come later if Jennie reprints often.
- Each card's QR opens the site with its code applied to the cart and UTM tags (source card, campaign pass-it-on / skicka-vidare). The code is also printed for typing. Applying a code from a link is a small feature of its own.
- Layout: business cards, 85x55 mm, 10 per A4 with crop marks, printed on thick paper and cut.

---

author: @claude
created: 2026-11-01 16:22

---

2026-11-01: Grilled and agreed with David. The code-from-link feature is TASK-164 and the card batch is TASK-165, both ready-for-agent. This task is the rollout.

---

author: @claude
created: 2026-11-05 08:18

---

TASK-164 closed without implementing on 2026-11-05; dependency removed.

---

author: @claude
created: 2026-11-05 08:40

---

2026-11-05: TASK-164 reopened; dependency restored.

---
<!-- COMMENTS:END -->
