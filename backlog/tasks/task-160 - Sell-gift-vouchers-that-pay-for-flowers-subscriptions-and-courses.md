---
id: TASK-160
title: 'Sell gift vouchers that pay for flowers, subscriptions and courses'
status: needs-triage
assignee: []
created_date: '2026-10-31 20:30'
updated_date: '2026-11-01 14:07'
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
Customers can buy an Eden Flowers gift voucher online or in the shop, and whoever receives it can spend it on flowers, subscriptions or courses.

**Why:** A voucher is the gift for someone whose taste you don't know, and it brings Christmas, birthday and corporate gift money to the shop rather than to a supermarket bouquet. It is paid for weeks before any flowers are made. Christmas 2026 is the obvious first season, so the first version should be ready by early December.

### Rough shape (to be grilled)

- **Buying.** A voucher is a product with fixed amounts (say 30, 50, 80 €) and maybe a free amount. Checkout asks for the recipient's name and a message, like the greeting card. No delivery, no fulfillment date.
- **What the recipient gets.** A beautifully set printable card (PDF) emailed to the buyer, or straight to the recipient on a chosen day. In the shop, Jennie can print one or hand over a physical card with the same code.
- **Spending.** The recipient enters the code at checkout (or Jennie enters it on a Custom Order). It pays like money, not like a Promotion: it is recorded as a Payment with a new `PaymentMethod`, and whatever is not spent stays on the voucher for next time.
- **Balance.** The recipient can check what is left from the code alone, without an account.

### Open questions

- **VAT and accounting.** In Finland a multi-purpose voucher (usable on goods at different VAT rates, like flowers and courses) is taxed when spent, not when sold. Confirm with the accountant, and decide how the monthly report shows vouchers sold, spent and outstanding.
- **Expiry.** Finnish consumer practice expects a long validity; pick one (e.g. two years) and print it on the card.
- **Refunds.** Can a voucher be refunded, and what happens when an order paid with one is cancelled: back onto the voucher?
- **Can one order use a voucher and a promotion code together?**
- **Domain language.** Add "Gift voucher" to `CONTEXT.md`, distinct from the greeting card (the "gift card" slot in checkout) and from a Promotion.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A customer can buy a gift voucher online and receive a printable card with its code
- [ ] #2 Jennie can sell a voucher in the shop as a Custom Order
- [ ] #3 A voucher pays for an Online Order, Custom Order or Course booking as a Payment, keeping any unspent amount
- [ ] #4 Anyone with the code can see what is left on it
- [ ] #5 The monthly report shows vouchers sold, spent and outstanding as the accountant needs
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-01 14:07

---

From the TASK-162 review (2026-11-01): Finnish companies usually settle Christmas gifts by mid to late November. Live in early December suits private buyers, but corporate voucher sales need it by about 20.11, or they wait until next year.

---
<!-- COMMENTS:END -->
