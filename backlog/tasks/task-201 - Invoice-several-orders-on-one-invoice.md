---
id: TASK-201
title: Invoice several orders on one invoice
status: needs-triage
assignee: []
created_date: '2026-11-26 08:05'
labels:
  - spec
dependencies: []
references:
  - CONTEXT.md
  - lib/edenflowers/payments/invoice.ex
  - lib/edenflowers/payments/changes/issue_invoice.ex
type: feature
ordinal: 366000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## Why

A business customer wants a bouquet delivered every week (a Repeating order, branch `repeat-custom-order`) and wants to pay by one invoice a month. Today an Invoice bills at most one order (`Invoice.order_id`). The workaround is a standalone invoice with the lines typed in by hand, but its orders stay unpaid, aren't locked and aren't tied to it.

## Decided

- **Jennie picks the orders.** No monthly job drafts the invoice for her.
- **No payment split.** Money paid on an invoice is the invoice's, never the order's (`Order.invoices`). Issuing marks each covered order Invoiced and takes it off its Balance, as it does now for one order. Partial payments stay on the invoice.

## Sketch

1. **Link table instead of `invoice.order_id`.** An order can be invoiced again after a Credit note, so the link isn't a column on Order. The link records the amount billed for that order at issue. `Order.invoiced?`, `amount_invoiced`, `invoiceable?` and locking go through it, and a Credit note still unlocks every covered order.
2. **Issuing** (`Payments.Changes.IssueInvoice`) locks every linked order, checks each is `invoiceable?`, and requires the invoice total to equal the sum of their Balances, the same rule as for one order today.
3. **The draft is filled from several orders** (`Changes.PrefillFromOrder`): one line per order with its date and order number, plus its Delivery or Pickup fee. A cancelled order bills its cancellation charge, as now.
4. **Picking orders.** "Create invoice" on an order offers the same customer's other `invoiceable?` orders, with tick boxes, defaulting to the same calendar month.
5. **Data migration.** Existing invoices with an `order_id` get a link row. It touches production data, so run `just backup` first.

Code that depends on the single order today: `lib/edenflowers/payments/invoice.ex`, `lib/edenflowers/payments/changes/issue_invoice.ex`, `lib/edenflowers/payments/validations/invoice_payment.ex`, plus PubSub `Events.admin_order(:order_id)`.

## Open questions (to grill)

- What counts as the same customer: the account (`user_id`), the email, or the company on the invoice?
- Date of supply for several dates: a range, or the last date?
- What the order number shows when there are several, and whether `customer_reference` stays free text.
- Can Jennie add an order to a draft later, or remove one? What happens to a draft whose order was edited or cancelled before issue?
- Should standalone invoices with hand-typed order lines be linked retroactively? Probably not.
- Order page and register: how an order shows the shared invoice.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Jennie can create one draft invoice from several invoiceable orders of the same customer, choosing which ones
- [ ] #2 Issuing it marks every chosen order Invoiced and locks them, and refuses if any order changed or is no longer invoiceable
- [ ] #3 A Credit note for it unlocks every order it covered
- [ ] #4 Bank transfers recorded on it settle the invoice and never change the orders' Balances
- [ ] #5 Existing single-order invoices behave exactly as before after the migration
<!-- AC:END -->
