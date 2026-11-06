---
id: TASK-160.3
title: Sell vouchers and record voucher payments in admin
status: done
assignee: []
created_date: '2026-11-01 17:32'
updated_date: '2026-11-06 09:52'
labels: []
dependencies:
  - TASK-160.1
parent_task_id: TASK-160
type: feature
ordinal: 309000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie sells in the shop and takes many orders by phone, so vouchers have to work on Custom Orders and manual course bookings too.

- Recording a payment offers Voucher: Jennie enters the code, and it pays min(what's left, Balance) like checkout. A Custom Order can also take a code when it's placed.
- Selling a voucher in the shop has its own admin form, not a line on a Custom Order.

## Decisions (grilled 2026-11-06)

**Its own form, its own order.** "Sell gift voucher" creates a voucher-only Order, the same kind the online voucher checkout makes, so the monthly report (vouchers sold vs sales), refunds and the order page's Gift voucher card work unchanged. A voucher never shares an order with flowers, so no payment has to be split between vouchers sold and sales. Buying both means two orders.

**Who uses it.** Mostly older customers in the shop, paying by card or cash. Jennie writes the code, amount and last day onto a preprinted card by hand, reading them from the voucher's order page, where she lands after saving.

**Fields**
- Buyer: name, phone, email. A phone or an email is required.
- Recipient: full name (optional, recommended) and email (optional).
- Amount: any amount from 20 EUR, no upper limit (online stays 20-200 in steps of 10).
- Message: optional, printed only on the emailed PDF.
- Language of the PDF and email: Jennie picks, Swedish first.
- Send the voucher PDF to: tick boxes for the buyer and the recipient, each offered when that email is filled in.
- Payment: card (Zettle) or cash, recorded with the sale. Paid on the spot only; no unpaid shop voucher.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Jennie can pay a Custom Order or course booking with a voucher code
- [x] #2 Sell gift voucher form records a paid voucher-only order and lands on its page
- [x] #3 The voucher PDF is emailed to the buyer, the recipient, both or neither, as Jennie ticks
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-05 20:09

---

The monthly report treats an order as a voucher sale only when it holds a voucher line and nothing else (gift_voucher_sale?, empty VAT breakdown). If a Custom Order can mix a voucher with flowers, its payments must be split between vouchers sold and sales, or keep vouchers on their own order.

---
<!-- COMMENTS:END -->
