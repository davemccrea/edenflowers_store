---
id: TASK-14
title: Refund an unhappy customer on a fulfilled order or booking
status: needs-info
assignee: []
created_date: '2026-10-17 18:40'
updated_date: '2026-10-18 05:48'
labels: []
dependencies: []
ordinal: 40000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Refund part or all of a fulfilled order or a course booking when the customer isn't happy, without it reading as owed again

### Problem

A customer who isn't happy with a fulfilled order may get some or all of their money back. Payment-balance decision 3 refuses a refund on anything that still stands until it's lowered or cancelled, but `edit` and `cancel` both refuse a fulfilled order, so Jennie can't record the refund at all. A refund she makes in the Stripe dashboard instead is recorded and pushes the balance positive, so the order reads "To collect" on the Overview and the order page, as if the customer owed the refund back.

The reason for refusing doesn't hold. The monthly report is cash-basis VAT (monthly-report decision 3): income is payments in the month they happen, and a refund is a negative row in its own month at the order's VAT rate. Lowering the order first adds nothing for the accounts.

### Decisions

1. **A goodwill refund is money handed back without lowering what was sold.** It's a refund `Payment` marked `goodwill`. It leaves the balance where it was, so the order or booking stays settled, and a goodwill refund of everything received reads `refunded?` (payment status "Refunded"). It's still a negative row in the monthly report.
   It lives in `Edenflowers.Payments.Payable`, so orders and bookings both get it.

2. **Jennie gives one once nothing is to collect, up to what was received.** On a record that's committed, not cancelled and has `balance <= 0`, capped at what was received less what's already been handed back (goodwill or not). A record with something to collect still refuses a refund (`Validations.Recordable`); a mistake is still corrected with Undo.
   - **Stripe:** refunds that amount through Stripe, reusing `Payments.refund/2`'s spreading over the Stripe payments, and the webhook records it. Capped at what was paid through Stripe less what Stripe already refunded.
   - **Any other method:** records it, capped at `paid_outside_stripe`, as `Validations.Recordable` does today.
   - A goodwill refund Jennie recorded can be undone like any other payment.

3. **A Stripe refund beyond what was owed back is goodwill.** `record_stripe_refund` marks the part beyond `-balance` as goodwill, so a refund made in the Stripe dashboard on a settled order no longer reads as "To collect". A refund that straddles (owed back €20, refunded €50) is €20 ordinary and €30 goodwill; split it into two rows (the `unique_stripe_refund` identity then includes `goodwill`) or store the goodwill part as an amount on one row, whichever reads simpler. This replaces decision 3's "one beyond what was owed back leaves a balance to collect".

4. **Where Jennie does it.** "Refund" in the order page's menu and in the booking's ⋯ menu on the courses page, shown when decision 2 allows one. A small form: amount (prefilled with nothing), how (Stripe when anything was paid through it, otherwise the outside-Stripe methods), confirm naming the amount. The order log reads "Goodwill refund €X · how"; the payments list labels it the same way.

### Open question

- Should Jennie give a short reason ("Customer unhappy with the bouquet"), shown in the order log? Needs a `note` on `Payment`. Undecided; see the ticket's comments.

### Out of scope

- A credit note or email to the customer. Stripe emails its own refund receipt; anything else Jennie writes herself.
- Refunding a pending order without editing it. Lowering the order stays the way there, so the receipt matches.
<!-- SECTION:DESCRIPTION:END -->
