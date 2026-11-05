---
id: TASK-165
title: Print pass-it-on cards with one-use promo codes
status: ready-for-agent
assignee: []
created_date: '2026-11-01 16:22'
updated_date: '2026-11-05 09:15'
labels:
  - customers
  - admin
dependencies:
  - TASK-164
priority: medium
type: feature
ordinal: 305000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A mix task or rpc creates a batch of one-use 15% promo codes and renders them into a print-ready PDF of bilingual 'pass it on' cards with Typst.

**Why:** The cards in gift deliveries (TASK-162.3) need a unique code each, and a QR code that takes the recipient to the shop. Typst already renders receipts in production, so the same tooling makes a print-ready sheet without a design tool.

Decisions (grilled 2026-11-01 with TASK-162.3):
- One batch per run. A name (e.g. 'Skicka vidare 2026-11') and a count (first run: 100). Each code is a Promotion with usage_limit 1, 15% off, no minimum, usable on any order. It has no expiration date when printed: it gets one 30 days after its first scan (TASK-165.2, replacing the 1 Nov 'no end date' decision).
- Run by David as a mix task or release rpc. An admin button only if Jennie reprints often. The PDF has to reach David's machine (rendered locally from the created codes, or copied out of the container); choose during implementation.
- Card: 85x55 mm, printed on both sides, 10 per A4 with crop marks, the back of each sheet mirrored to line up with its front.
  - Front: the message in Swedish, then Finnish.
  - Back: the QR code, the code with a short line saying to enter it at checkout and that it's valid for 30 days after the first scan, edenflowers.fi and @edenflowers.fi.
- QR target: a 'Pass it on' landing page, e.g. https://edenflowers.fi/pass-it-on?code=<the card's code>&utm_source=card&utm_medium=print&utm_campaign=pass-it-on. The printed URL never changes, so the suggestion can change without reprinting. The exact path (it is printed on bilingual cards, so it can't follow one language) is chosen during implementation with the route translations.
- The landing page (reviewed with the referrals skill, 2026-11-05):
  - Opens on the moment, e.g. 'You were just given flowers from Eden Flowers'. A card Jennie linked to its order greets the recipient by first name ('Hi Anna, ...', TASK-165.1). Never the sender's name: there's no anonymous-gift option and some card messages are unsigned on purpose. Then the heading 'Pass it on', the recipient's code and its 15% off for a gift.
  - One suggested product: the first of Jennie's Favourite products (the `featured` read, in store order). No new admin setting. Its button goes straight to that product, not the shop front, since the code is already on the cart.
  - A quiet 'see all bouquets' link under it, for people who want something else or flowers for themselves.
  - A short terms line: one code per order, can't be combined with other codes (checkout already enforces this).
  - TASK-164 puts the code on the cart as on any storefront page; the code is also printed on the card for typing at checkout.
- A used or unknown code still shows the page and the product, without claiming a discount.
- QR codes from a Typst package (e.g. tiaoma) vendored into priv, so production never downloads it. Typst theme matches the receipts (priv/receipts/theme.typ).

Draft text (agent-written in Jennie's voice; she approves before the first print):
Front:
S K I C K A  V I D A R E 💛
Någon tänkte på dig idag. Skicka glädjen vidare: ge blommor till någon du tycker om, med 15 % rabatt.
A N N A  E T E E N P Ä I N 💛
Joku ajatteli sinua tänään. Anna ilo eteenpäin: lähetä kukkia jollekulle tärkeälle 15 % alennuksella.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 One run creates the requested number of one-use 15% codes under a batch name
- [ ] #2 It produces an A4 PDF of 85x55 mm double-sided cards, 10 per sheet, with crop marks
- [ ] #3 Each card's QR code opens the 'Pass it on' page with its own code and the pass-it-on UTM tags, and the code is also printed on the card
- [ ] #4 The 'Pass it on' page shows the visitor's code and Jennie's first Favourite product, and a used or unknown code shows no discount
- [ ] #5 The page opens on the gift moment, links its suggestion straight to the product with a 'see all bouquets' link below, and states the one-code-per-order terms
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-05 08:18

---

TASK-164 (apply a promo code from a link) was closed without implementing on 2026-11-05, so the QR's ?code= no longer applies the code by itself.

---

author: @claude
created: 2026-11-05 08:40

---

2026-11-05: TASK-164 reopened (closed by accident). The QR carries the card's code again, so it's applied on scan; the printed code stays for typing. Considered and dropped: blank link cards Jennie scans to tie each card to its gift order, as the extra step per delivery isn't worth knowing which gift a card came from.

---

author: @claude
created: 2026-11-05 08:43

---

2026-11-05: QR leads to a 'Pass it on' landing page (code + first Favourite product) so the printed URL survives product changes.

---

author: @claude
created: 2026-11-05 09:15

---

2026-11-05: Cards can be linked to their gift order (TASK-165.1, recipient's first name on the page) and codes expire 30 days after first scan (TASK-165.2). Card back mentions the 30 days.

---
<!-- COMMENTS:END -->
