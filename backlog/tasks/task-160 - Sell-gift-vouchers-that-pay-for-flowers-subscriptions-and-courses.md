---
id: TASK-160
title: 'Sell gift vouchers that pay for flowers, subscriptions and courses'
status: ready-for-agent
assignee: []
created_date: '2026-10-31 20:30'
updated_date: '2026-11-06 09:22'
labels:
  - spec
  - customers
  - admin
dependencies: []
priority: high
type: feature
ordinal: 295000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Customers can buy an Eden Flowers gift voucher online or in the shop, and whoever receives it can spend it on flowers, subscriptions and courses.

**Why:** A voucher is the gift for someone whose taste you don't know, and it brings Christmas, birthday and later corporate gift money to the shop rather than to a supermarket bouquet. It is paid for weeks before any flowers are made. On sale by 1.12.2026 for private Christmas buyers (TASK-162).

## Decisions (grilled 2026-11-01, trimmed in two Ponytail reviews)

**Model**
- A Gift voucher has a code, an amount and an expiry one year from purchase. What's left on it is its amount minus its `:voucher` payments, so there's no separate balance to keep in step.
- It pays like money, not like a Promotion: a new `PaymentMethod` `:voucher`, each payment pointing at its voucher, in the existing Payable ledger (ADR 0002).
- Buying one is an ordinary Order with a voucher line (ADR 0004: every sale is an order), so refunds and the report work as for any order.
- Codes are long and random (reusing the newsletter code generator, made longer), and the voucher lookup is rate-limited with ash_rate_limiter: a code is money.
- Add "Gift voucher" to `CONTEXT.md`, distinct from the greeting card (the "gift card" slot in checkout) and from a Promotion.

**Buying**
- Online: its own one-page voucher checkout, like course booking, built on an Order and the existing Stripe PaymentIntent flow. It asks for an amount (20-200 EUR in steps of 10), the recipient's name, a message and the buyer's email. A voucher can't share a cart with flowers.
- The buyer gets a PDF by email: amount, code, expiry, recipient and message, in sv and fi, set in Typst with the receipts' theme.
- Optional checkbox, 'collect a printed card at Minimossen'. The confirmation email says it's ready from the next opening day. A badge on the order tells Jennie to print it; there is no separate list.
- In the shop: its own 'Sell gift voucher' admin form makes a voucher-only order, paid by card or cash on the spot (TASK-160.3).

**Spending**
- A separate 'Gift voucher' field in the payment step of checkout and course checkout. The promo field stays as is, and a promo and a voucher can both apply.
- The voucher pays min(what's left, Balance) as a `:voucher` payment, and Stripe charges the rest. A purchase fully covered by a voucher is placed through the same path as a Stripe success, with no Stripe.
- Jennie records voucher payments on Custom Orders and manual course bookings by choosing Voucher and entering the code, as she records cash.
- Subscriptions: the voucher is stored on the subscription, and checkout still saves a card. Each order the subscription creates draws from the voucher first, then the card, with the usual heads-up email.

**Refunds**
- A voucher is not refundable and never paid out in cash (decided 2026-11-05). An online buyer keeps the 14-day right of withdrawal while it is unspent, which Jennie honours by cancelling its order.
- When an order paid by voucher is cancelled or refunded, the voucher's part goes back onto the voucher as a negative `:voucher` payment.

**VAT and report**
- Designed as a multi-purpose voucher, as Shopify and WooCommerce do: no VAT when sold, and VAT on what it buys, at each item's rate (rates differ, e.g. chocolate). The accountant confirms.
- The monthly report counts payments as sales, so payments for a voucher count as vouchers sold (held for later, not sales), and `:voucher` payments count as sales when spent.

**Terms of sale:** a short voucher section (valid one year, not refundable or exchangeable for cash, 14-day withdrawal for online purchases while unspent) in sv/fi/en.

**Not now:** a public page showing what's left on a voucher (checkout and receipts show it), vouchers on Payment Links, emailing the recipient on a chosen day, 'outstanding' in the report (add when the accountant asks), corporate sales before Christmas.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-01 14:07

---

From the TASK-162 review (2026-11-01): Finnish companies usually settle Christmas gifts by mid to late November. Live in early December suits private buyers, but corporate voucher sales need it by about 20.11, or they wait until next year.

---

author: @claude
created: 2026-11-01 16:46

---

Grilling round 1-2 (2026-11-01):
- On sale by 1.12 for private buyers. Corporate Christmas buyers wait until next year.
- VAT: designed as multi-purpose vouchers, as Shopify and WooCommerce do. No VAT when sold; VAT on what the voucher buys, at each item's rate (chocolate add-ons are food, so rates differ). David asks the accountant to confirm in parallel. Consequence: the monthly report counts payments as sales (ADR 0002), so money paid for a voucher must count as held for later, and voucher payments must count as sales when spent.
- Valid one year from purchase, printed on the card.
- An online buyer always gets a PDF card by email, and can choose to collect a printed card in the shop.
- Amounts: a free amount in steps of 10 EUR.
- Spend anywhere: Online Orders, Custom Orders, course bookings. A subscription can be started with a voucher, and each order it creates draws from the voucher before the card is charged. David asked for a Ponytail review of this scope.

---

author: @claude
created: 2026-11-01 17:06

---

Round 3 (2026-11-01), after the Ponytail review:
- Core: a Voucher plus a :voucher payment method, with each voucher payment pointing at its voucher. What's left on a voucher is its amount minus its payments. One 'pay from voucher' step records min(what's left, what's owed) as a payment before any Stripe charge, in checkout, course checkout and the subscription's order charge (the voucher is stored on the subscription). Fully covered purchases are placed without Stripe.
- Cut: amounts are the voucher product's sizes, 20-200 EUR in steps of 10. A printed card is collected through ordinary pickup, with Jennie printing the PDF. No public page for what's left (checkout and receipts show it). No voucher on Payment Links: Jennie records a voucher payment by method and code, as she records cash.
- A voucher and a promo code can be used together: the promo lowers the price, the voucher pays.
- A bought voucher can be refunded while unspent, by Jennie cancelling its order. No cash refund once any of it is spent.
- When an order paid by voucher is cancelled or refunded, the voucher's part goes back onto the voucher as a negative voucher payment.

---

author: @claude
created: 2026-11-01 17:25

---

Round 4-5 (2026-11-01):
- A subscription started with a voucher always saves a card at checkout. Its orders draw from the voucher, then the card, and the existing heads-up email warns before each charge.
- Two code fields. The promo field stays as is, and a 'Gift voucher' field sits in the payment step beside the card (checkout and course checkout). We discussed why Shopify combines them: less clutter, and one code engine across millions of shops. Not worth the extra logic here.
- The voucher PDF shows the amount, code, expiry, recipient's name and the buyer's message, in sv and fi, set in Typst.
- Vouchers are bought through their own short checkout, like course booking, not the cart: amount (20-200 EUR in steps of 10), recipient name, message, the buyer's email, then card payment. A voucher can't share a cart with flowers.
- Printed card: a checkbox, 'collect a printed card at Minimossen'. The confirmation email says it can be collected from the next opening day. Jennie prints it from a list in admin.

---

author: @claude
created: 2026-11-01 17:32

---

2026-11-01: Grilled and agreed with David, then trimmed in a Ponytail review. Split into subtasks TASK-160.1 to .6.

---
<!-- COMMENTS:END -->
