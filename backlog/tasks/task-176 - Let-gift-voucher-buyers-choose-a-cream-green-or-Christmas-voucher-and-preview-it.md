---
id: TASK-176
title: >-
  Let gift voucher buyers choose a cream, green or Christmas voucher and preview
  it
status: in-progress
assignee: []
created_date: '2026-11-06 13:43'
updated_date: '2026-11-06 13:45'
labels:
  - customers
  - admin
dependencies:
  - TASK-177
priority: medium
type: feature
ordinal: 341000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Gift voucher buyers choose the look of their voucher PDF (Regular, the cream one, or Christmas) and see a live preview of it with their amount, recipient and message. Jennie picks the style on the admin sale form.

**Why:** a voucher bought as a Christmas present, or forwarded rather than printed, deserves a voucher that looks the part, and seeing it before paying makes the buyer sure of what the recipient gets.

Decisions (grilled 2026-11-06):
- The style is stored on the sale order (voucher_style), set at sale, never changed after. Older sales and other orders print in cream.
- Cream, shown to customers as Regular, stays the default, as it prints well at home. A green style was tried and dropped.
- Christmas is cream with pale snowflakes over the whole card, clear of the small print, and a Great Vibes greeting (God Jul / Hyvää joulua / Merry Christmas) above the Gift voucher label. The buyer can reshuffle the snow ("Let it snow"); the order keeps its voucher_snow_seed so the PDF matches the preview.
- Jennie offers Christmas online with a switch on the shop calendar row (Fulfillments page). The admin form always offers both.
- The preview is the real Typst template rendered as a PNG, with a placeholder code and a year's validity from today. Customers only; the admin form has a style select and no preview.
- The style changes only the PDF, not the handwritten gift card at Minimossen.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A customer gets the Regular voucher on the voucher checkout, or chooses Christmas while Jennie offers it
- [x] #2 The checkout previews the voucher as it's filled in, in the chosen style and language
- [x] #3 The voucher PDF the buyer and recipient get is in the chosen style
- [x] #4 Jennie chooses any style on the admin sale form
- [x] #5 Jennie switches the Christmas style on and off for customers on Fulfillments
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Snowflakes are a World of Printables placeholder; TASK-177 must be resolved before deploying.
<!-- SECTION:NOTES:END -->
