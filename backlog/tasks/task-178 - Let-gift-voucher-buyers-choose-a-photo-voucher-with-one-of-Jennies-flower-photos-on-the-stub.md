---
id: TASK-178
title: >-
  Let gift voucher buyers choose a Golden hour voucher, with a flower photo on
  the stub
status: done
assignee: []
created_date: '2026-11-06 15:48'
updated_date: '2026-11-06 16:26'
labels:
  - customers
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 343000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Gift voucher buyers choose Golden hour beside Signature (the green, cream-sided voucher) and Christmas; its stub shows a warm autumn flower photo instead of brand green.

**Why:** a voucher with real flowers on it looks like a present from a florist, and gives buyers a second everyday look to choose from.

Decisions (grilled 2026-11-06):
- The photo replaces the green stub, darkened top, middle and bottom so the logo, amount and code read in cream. The cream side is unchanged.
- Golden hour is always offered online; Christmas stays behind Jennie's switch. Jennie's admin sale form offers every style.
- Golden hour uses Marie Lillhannus's photo (images/wedding/marie_lillhannus.jpg), cropped to the stub in priv/receipts/assets/photos/golden-hour.jpg. Fresh-cut and Cosmos photo styles were tried and dropped.
- The cream style is shown to customers as Signature. Christmas's stub is cranberry red, with a green rule under the name.
- Make it personal leads the page: style, then the preview (on a phone), then who it's for and the message.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The voucher PDF has the chosen photo on its stub, with the amount, code and last day readable
- [x] #2 Jennie chooses any style on the admin sale form
- [x] #3 A customer chooses Golden hour on the voucher checkout and sees it in the preview
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Later decisions (2026-11-06): Christmas comes in two styles, Christmas red (:christmas) and Christmas green (:christmas_green), each with one accent for its stub, greeting and snow; both behind Jennie's switch and both reshuffle their snow. No vouchers have a rule between the name and the message any more. Until the buyer types, the preview shows "Name here" and "Your message here" in the voucher's language. Style choices sit two to a row; Christmas options carry 🎁 and 🎄.
<!-- SECTION:NOTES:END -->
