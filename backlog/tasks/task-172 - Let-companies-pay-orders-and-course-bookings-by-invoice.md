---
id: TASK-172
title: Let companies pay orders by invoice
status: done
assignee: []
created_date: '2026-11-03 19:30'
updated_date: '2026-11-03 21:13'
labels:
  - spec
  - admin
  - customers
dependencies:
  - TASK-168
priority: high
type: feature
ordinal: 330000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A company can order a bouquet and pay by invoice: Jennie issues an ordinary invoice for that order, and the order counts it as covering its balance.

**Why:** Companies in Finland commonly ask to pay by invoice, and one already has. Today Jennie would have to make an order plus an unrelated invoice: one of them shows a balance forever, or the sale and its VAT get counted twice in the monthly report.

## Decided (2026-11-03)
- **An invoice stays one kind: a standalone sale.** Its own lines, VAT, payments, credit notes and receivables, exactly as built in TASK-168. The only addition is an optional link to one order (`order_id`). Weddings, bespoke work and private courses keep using unlinked invoices.
- **The order subtracts its invoices.** `Order` gets `has_many :invoices` and an `amount_invoiced` aggregate: the amounts of its issued invoices that have no credit note. `Payable`'s `balance` subtracts `amount_invoiced`, which a course booking supplies as 0. Money for an order is collected either on the order or through its invoice, and each euro is counted where it arrived.
- **Which orders:** a custom order on the existing bank-transfer terms (`payment_terms: :invoice`) with nothing paid, a Balance above 0 and no uncredited issued invoice. An `invoiceable?` calculation on the order says so; the admin shows Create invoice from it and issuing a linked invoice validates against it. A part-paid order is refused. To invoice an order on other terms, Jennie switches its terms first. Online orders never have these terms, so checkout is unchanged.
- **Prefill:** the draft takes the order's buyer, locale and lines: one invoice line per order line at its own price and VAT rate, plus a Delivery line at `fulfillment_tax_rate` when there is a fee. Custom orders never carry a promotion, so invoices need no discount support; a reduction for a company is a custom line on the order. Supply date (toimituspäivä) is the fulfillment date and supply description "Order #N", which the PDF shows as the reference. All editable in the draft, where Jennie adds company details (company name, Y-tunnus, billing address, customer reference).
- **Cancelled order:** the prefill is "Cancellation charge, order #N" for its Balance, one line per VAT rate, split in proportion to the order's VAT breakdown.
- **One rule against over- and under-invoicing (2026-11-03, revised):** issuing a linked invoice is refused unless its amount equals the order's remaining balance. This refuses a draft left stale by an order edit, and never leaves a remainder that a second invoice couldn't collect. Lines may still be reworded or regrouped.
- **Locked while invoiced (2026-11-03, revised):** while an order has an issued invoice that is not credited (an `invoiced?` calculation), cancelling it is refused with "Credit the invoice first", and so is any edit that changes its amount per VAT rate (VAT breakdown), its fulfillment date (the invoice's date of supply) or its payment terms. Edits that keep those, such as renaming a line, a new address that keeps the fee or new contact details, are allowed: the invoice's wording can differ from the order's anyway. A paid invoice can't be credited; those corrections go to the accountant, as today.
- **Cancellation:** Jennie credits the unpaid invoice with the existing credit note action, which unlocks the order. She cancels it, the Balance becomes the cancellation charge, and she invoices that the same way.
- **Balance means "left to collect here", not "paid".** An invoiced order shows 0 before the money arrives. The admin order page shows the linked invoices with their status (open, paid, overdue, cancelled). Fulfillment never depended on payment (ADR 0001), and overdue invoices are chased from the invoices list.
- **Copy:** the Order details email for bank-transfer terms says an invoice follows after delivery (en/fi/sv, checked with `mix print_emails`). The admin labels the terms "Invoice after delivery".
- Money paid on an invoice is refunded or corrected on the invoice side, which means via the accountant for paid invoices, as today. The order's refund actions only see its own payments.
- Monthly report, receivables and invoice code are unchanged apart from the link.
- Update ADR 0004 and CONTEXT.md (Invoice, Balance, Payment) to say an invoice can be for an order and that it reduces its Balance.

## Considered and rejected
- Linking invoices to course bookings: a company's course is a private course, not a website Course, so Jennie invoices it unlinked.
- Invoice as a bill whose payments are recorded on the order: needs locked lines, refused invoice payments and a `paid?` that follows the order, all inside the invoice code.
- Payments on the invoice that the order's payment sums also read: tangles refunds across two records.
- Invoicing orders on any terms, or part-paid orders: the prefill would not match the Balance, and a payment-link order would email a link the invoice later closes.
- A discount row or per-line discount on invoices, to mirror the receipt: linked orders are custom orders, which never carry a promotion.
- Allowing edits or cancelling while invoiced and showing a negative Balance: it reads as money to refund that the order never held.
- Weddings as custom orders: a wedding is a quote whose price settles late, and order emails don't fit it.
- Removing bank-transfer terms from orders: companies commonly need invoices, and the workaround double counts.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 From a custom order on bank-transfer terms with nothing paid and a balance, Jennie can create, issue, email and download a linked invoice prefilled with its buyer, lines, a Delivery line, supply date and order number
- [x] #2 Orders on other terms, part-paid orders and orders with an uncredited issued invoice offer no Create invoice, and issuing a linked invoice for them is refused
- [x] #3 Issuing a linked invoice reduces the order's balance by its amount; issuing one for any other amount than the remaining balance is refused
- [x] #4 While a linked invoice is issued and not credited, cancelling the order and edits that change its amount per VAT rate, date or terms are refused with Credit the invoice first; other edits are allowed
- [x] #5 Crediting a linked invoice restores the order's balance; after cancelling, the invoice prefill is the cancellation charge split per VAT rate
- [x] #6 Payments on a linked invoice count in the monthly report once, with the invoice's VAT, and an unpaid one appears in month-end receivables
- [x] #7 The admin order page shows its invoices and each one's status
- [x] #8 The Order details email for bank-transfer terms says an invoice follows after delivery in en, fi and sv, and the admin labels the terms Invoice after delivery
- [x] #9 Unlinked invoices for weddings, bespoke work and private courses behave as before
<!-- AC:END -->
