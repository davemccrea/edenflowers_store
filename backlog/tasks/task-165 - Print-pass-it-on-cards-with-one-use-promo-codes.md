---
id: TASK-165
title: Print pass-it-on cards with one-use promo codes
status: ready-for-agent
assignee: []
created_date: '2026-11-01 16:22'
updated_date: '2026-11-05 08:18'
labels:
  - customers
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 305000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A mix task or rpc creates a batch of one-use 15% promo codes and renders them into a print-ready PDF of bilingual 'pass it on' cards with Typst.

**Why:** The cards in gift deliveries (TASK-162.3) need a unique code each, and a QR code that applies it. Typst already renders receipts in production, so the same tooling makes a print-ready sheet without a design tool.

Decisions (grilled 2026-11-01 with TASK-162.3):
- One batch per run. A name (e.g. 'Skicka vidare 2026-11') and a count (first run: 100). Each code is a Promotion with usage_limit 1, 15% off, no expiration date, no minimum, usable on any order.
- Run by David as a mix task or release rpc. An admin button only if Jennie reprints often. The PDF has to reach David's machine (rendered locally from the created codes, or copied out of the container); choose during implementation.
- Card: 85x55 mm, printed on both sides, 10 per A4 with crop marks, the back of each sheet mirrored to line up with its front.
  - Front: the message in Swedish, then Finnish.
  - Back: the QR code, the code printed for typing, edenflowers.fi and @edenflowers.fi.
- QR target: https://edenflowers.fi/?code=<code>&utm_source=card&utm_medium=print&utm_campaign=pass-it-on.
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
- [ ] #3 Each card's QR code opens the site with its own code and the pass-it-on UTM tags
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-05 08:18

---

TASK-164 (apply a promo code from a link) was closed without implementing on 2026-11-05, so the QR's ?code= no longer applies the code by itself.

---
<!-- COMMENTS:END -->
