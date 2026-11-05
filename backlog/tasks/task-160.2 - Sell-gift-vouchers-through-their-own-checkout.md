---
id: TASK-160.2
title: Sell gift vouchers through their own checkout
status: done
assignee: []
created_date: '2026-11-01 17:32'
updated_date: '2026-11-05 20:04'
labels: []
dependencies:
  - TASK-160.1
parent_task_id: TASK-160
type: feature
ordinal: 308000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Christmas buyers need to buy a voucher online by 1.12 without going through flower delivery steps.

- A one-page voucher checkout built on an Order with a voucher line and the existing Stripe PaymentIntent flow: amount 20-200 EUR in steps of 10, recipient name, message, buyer email, card.
- Placing the order creates the voucher (expiry one year) and emails a Typst PDF (amount, code, expiry, recipient, message; sv and fi; receipts' theme).
- Checkbox 'collect a printed card at Minimossen': the email says it's ready from the next opening day, and the order shows a badge for Jennie to print it.
- A link to the voucher checkout from the store.
- Terms of sale: a short voucher section (valid one year, refundable while unspent, no cash for a part-spent voucher), sv/fi/en.
- Cancelling an unspent voucher's order refunds it and stops the voucher.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A buyer can buy a voucher online and receives its PDF by email
- [x] #2 Choosing to collect shows a badge on the order and says so in the email
- [x] #3 The terms of sale describe vouchers
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-11-05 (WIP commit): A voucher sale is an Online Order with one voucher line, started at payment and never a browser's cart; placing it issues the voucher. Emailed vouchers are placed fulfilled; 'collect a gift card at Minimossen' keeps the order open, and Jennie writes the recipient and code on one of her ready-printed cards (no printing). The buyer chooses the PDF's language (sv/fi/en). The email attaches the voucher PDF and the receipt, which marks the voucher as not subject to VAT, with no VAT rows. Cancelling refunds and stops the voucher while it's unspent; partial refunds of a voucher sale are refused.

2026-11-05 (no refunds): Vouchers are not refundable. The terms now say a voucher can't be refunded or exchanged for cash, and an online buyer can still cancel within 14 days while it's unspent (the statutory right of withdrawal), which Jennie does by cancelling its order. The voucher page has a new opening line. sv/fi updates are added to T26/T27.

2026-11-05 (verified): Bought a 50 € Swedish voucher with collect-a-card in the browser on Stripe test mode. The email carried the voucher PDF and the receipt and named the card's ready day; the admin order showed 'Card to write' with the code to copy. The confirmation page now gives one passive paragraph with the ready day, from Order's voucher_card_ready_on, which the email reads too.
<!-- SECTION:NOTES:END -->

2026-11-05 (admin): A voucher sale's admin page shows a Gift voucher card (recipient, amount, code, expiry, message) in place of the fulfillment and items; a card to collect has a 'Card to write' badge on the page and in the orders list until Jennie marks it collected. The list shows 'Gift voucher' for its date and no method. Both pages crashed on a voucher sale before, having no fulfillment date.

2026-11-05 (store link, terms): The store's category bar ends with a Gift voucher link to the voucher checkout. The terms of sale have a Gift vouchers section (valid one year, refunded in full while unspent, no cash for the rest of a part-spent voucher), sv/fi AI-drafted and queued as T26 for Jennie and native review. The terms say a voucher pays for subscriptions, as the voucher page does; that needs TASK-160.4 before release.

2026-11-05 (translations): The voucher page, its order page lines, the voucher email and the route (/sv/presentkort, /fi/lahjakortti) are AI-drafted in sv/fi and queued as T27. A LiveView test covers buying a voucher in Swedish, changing the amount and starting the card payment. Still to do: the manual Stripe test-mode smoke check (docs/agents/testing.md) of a real voucher purchase and its emailed PDF, then tick #1 and #2.
