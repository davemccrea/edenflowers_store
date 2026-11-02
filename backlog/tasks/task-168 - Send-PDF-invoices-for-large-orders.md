---
id: TASK-168
title: Send PDF invoices from the shop instead of Zervant
status: ready-for-human
assignee: []
created_date: '2026-11-01 20:39'
updated_date: '2026-11-02 13:55'
labels:
  - spec
  - admin
  - customers
dependencies: []
priority: medium
type: feature
ordinal: 314000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie can invoice any order or Course booking on invoice terms straight from the shop admin: the shop makes the PDF, emails it to the customer and tracks it until it is paid by bank transfer.

**Why:** Larger orders such as weddings lose a noticeable cut to Stripe fees, and Finnish customers expect to be invoiced after delivery anyway. Today Jennie makes these invoices by hand in Zervant, outside the shop, and copies the payments back.

## Decisions

- **Replaces Zervant** for every order and Course booking on invoice terms (`payment_terms: :invoice`). No threshold or customer-type rule: Jennie decides per purchase.
- **Several invoices per purchase.** Jennie picks each invoice's amount. It defaults to the Balance not yet invoiced. This covers a wedding's booking fee about four weeks before, then the rest after delivery.
- **Contents:** the seller (Jennie McCrea, her registered address and Y-tunnus) in the footer, buyer details, invoice number and date, delivery date, due date, viitenumero, late payment interest (a fixed 8,00 %), the purchase's lines with VAT per rate (as on receipts), what has already been invoiced or paid, then "Due on this invoice". Payment block: IBAN, viitenumero, due date, amount, virtuaaliviivakoodi and bar code. No BIC: SEPA transfers need only the IBAN. No Payment Link: bank transfer only.
- **Numbering** is one sequential series that continues Zervant's (first shop number = Zervant's last + 1). The viitenumero is built from the invoice number with the Finnish check digit.
- **Due date** defaults to 14 days after the invoice date (`Payment.overdue_after_days`). Jennie can change it per invoice.
- **Buyer:** orders and Course bookings get a "Business customer" checkbox with company name, Y-tunnus, billing address (all three required) and an optional customer reference (viitteenne / PO). Missing details never block saving the order or booking, only creating an invoice. A consumer invoice needs only a name and email; a postal address is printed if the purchase has one. Each invoice freezes a copy of the buyer details it was sent with.
- **Language:** the purchase's locale (fi, sv, en). Jennie can change it when creating the invoice.
- **Delivery:** the shop emails the invoice with the PDF attached, and admin can download it too.
- **Immutable once sent.** Everything the PDF prints, seller details included, is frozen onto the invoice when it is made, so every download and resend is the same PDF. To correct one, Jennie cancels it. That issues a credit note (hyvityslasku) from the same number series naming the original, and she then sends a new invoice.
- **Payment:** Jennie records the bank transfer as a Payment against the invoice. The invoice is paid once its Payments cover its amount. The existing Payment received email still goes out. The Zervant payment method becomes a bank transfer invoice.
- **Overdue:** admin flags invoices past their due date. Jennie can resend one with a friendly reminder line. Nothing is sent automatically.
- **Accounting:** sales are still booked from orders (ADR 0004). The monthly report gains a list of invoices still unpaid at month end.
- **PDF:** Typst, like `Edenflowers.Orders.Receipt`.

## Out of scope

E-invoicing (verkkolasku/Finvoice), bank statement import and matching by viitenumero, automatic reminders. Add them when a customer or the volume needs them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Jennie can create, email and download an invoice for any order or Course booking on invoice terms
- [x] #2 An invoice for a business customer can't be created until company name, Y-tunnus and billing address are filled in
- [x] #3 Invoice numbers continue Zervant's series without gaps, and each has a valid viitenumero and virtual barcode
- [x] #4 Cancelling a sent invoice issues a credit note naming it
- [x] #5 Recording a bank transfer Payment against an invoice marks it paid once covered
- [x] #6 Admin flags overdue invoices and can resend them with a reminder line
- [x] #7 The monthly report lists invoices unpaid at month end
- [ ] #8 Zervant is no longer needed for shop sales
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Cancelling now asks for the cancellation charge Jennie keeps (0 to the Total due, paid or not) instead of a refund amount. Paid above it is refunded; any of it unpaid is left as a Balance to collect, which she invoices from the cancelled row. A booking's charge starts at the course's terms, an order's at 0.

The invoice PDF was simplified after comparing with Zervant's invoice 1336: no buyer email, order number, subtotal, BIC or payee field; the delivery date, viitenumero and late payment interest are facts beside the buyer; the VAT table always shows; the payment block has IBAN, viitenumero, due date, amount, virtual barcode digits and bar code. The seller (name, address, Y-tunnus, IBAN) lives in config :edenflowers, :seller, which receipts and invoices both print; shop.toml keeps only the pickup place and contact details.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-01 23:14

---

All subtasks done on branch pdf-invoices. Left before go-live: set Zervant's last invoice number + 1 (>= 100) and the real IBAN and BIC in config :edenflowers, :invoices; review fi/sv drafts R05, R06, R07, T21, T22, T23 in priv/gettext/review-queue.md and the untranslated invoice admin strings; build the release image once to confirm offline Typst rendering. AC 8 (Zervant no longer needed) is checked once that's done.

---

author: @claude
created: 2026-11-02 13:55

---

Go-live config done: invoices continue Zervant's series from 1337 (its last was 1336), and the seller is Jennie McCrea, Stadsgatan 3, 65300 Vasa, with her real IBAN FI69 3939 0018 3959 05, in config :edenflowers, :seller (receipts print it too). BIC dropped: SEPA transfers need only the IBAN. Late payment interest is a fixed 8,00 %. Still left before go-live: review fi/sv drafts R05, R06, R07, R09, T21, T22, T23 in priv/gettext/review-queue.md and the untranslated invoice admin strings; build the release image once to confirm offline Typst rendering. AC 8 (Zervant no longer needed) is checked once that's done.

---
<!-- COMMENTS:END -->
