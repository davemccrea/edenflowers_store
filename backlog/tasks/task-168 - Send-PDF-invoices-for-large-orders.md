---
id: TASK-168
title: Send PDF invoices from the shop instead of Zervant
status: ready-for-agent
assignee: []
created_date: '2026-11-01 20:39'
updated_date: '2026-11-01 20:56'
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
- **Contents:** seller details (name, Y-tunnus, address, IBAN, BIC from config), buyer details, invoice number and date, due date, the purchase's lines with VAT per rate (as on receipts), what has already been invoiced or paid, then "Due on this invoice". Payment block: IBAN, BIC, viitenumero, virtuaaliviivakoodi, and the standard late-interest line (viivästyskorko korkolain mukaan). No Payment Link: bank transfer only.
- **Numbering** is one sequential series that continues Zervant's (first shop number = Zervant's last + 1). The viitenumero is built from the invoice number with the Finnish check digit.
- **Due date** defaults to 14 days after the invoice date (`Payment.overdue_after_days`). Jennie can change it per invoice.
- **Buyer:** orders and Course bookings get a "Business customer" checkbox with company name, Y-tunnus, billing address (all three required) and an optional customer reference (viitteenne / PO). Missing details never block saving the order or booking, only creating an invoice. A consumer invoice needs only a name and email; a postal address is printed if the purchase has one. Each invoice freezes a copy of the buyer details it was sent with.
- **Language:** the purchase's locale (fi, sv, en). Jennie can change it when creating the invoice.
- **Delivery:** the shop emails the invoice with the PDF attached, and admin can download it too.
- **Immutable once sent.** To correct one, Jennie cancels it. That issues a credit note (hyvityslasku) from the same number series naming the original, and she then sends a new invoice.
- **Payment:** Jennie records the bank transfer as a Payment against the invoice. The invoice is paid once its Payments cover its amount. The existing Payment received email still goes out. The Zervant payment method becomes a bank transfer invoice.
- **Overdue:** admin flags invoices past their due date. Jennie can resend one with a friendly reminder line. Nothing is sent automatically.
- **Accounting:** sales are still booked from orders (ADR 0004). The monthly report gains a list of invoices still unpaid at month end.
- **PDF:** Typst, like `Edenflowers.Orders.Receipt`.

## Out of scope

E-invoicing (verkkolasku/Finvoice), bank statement import and matching by viitenumero, automatic reminders. Add them when a customer or the volume needs them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Jennie can create, email and download an invoice for any order or Course booking on invoice terms
- [ ] #2 An invoice for a business customer can't be created until company name, Y-tunnus and billing address are filled in
- [ ] #3 Invoice numbers continue Zervant's series without gaps, and each has a valid viitenumero and virtual barcode
- [ ] #4 Cancelling a sent invoice issues a credit note naming it
- [ ] #5 Recording a bank transfer Payment against an invoice marks it paid once covered
- [ ] #6 Admin flags overdue invoices and can resend them with a reminder line
- [ ] #7 The monthly report lists invoices unpaid at month end
- [ ] #8 Zervant is no longer needed for shop sales
<!-- AC:END -->
