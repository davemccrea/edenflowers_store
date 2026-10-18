---
id: TASK-16
title: Decide whether course bookings become ordinary orders
status: done
assignee: []
created_date: '2026-10-18 03:08'
updated_date: '2026-10-18 14:18'
labels:
  - spec
  - developers
  - wontfix
dependencies: []
priority: medium
type: grilling
ordinal: 46000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Decide whether a course booking becomes an ordinary Order, so the shop has one sales record instead of two

**Why:** A course booking is a sale that isn't an order, so every piece of money code handles two kinds of record. Deciding settles whether that duplication stays.

### Problem

ADR 0004 says every sale the shop makes is an order, and the orders are the only record sales are booked from. A course booking (`CourseRegistration`) is a sale that isn't an order, so the sales record has two kinds of row, and everything that handles money handles both:

- `Payments` and `Payments.Payable`: per-resource branches (see `TASK-17`).
- `Orders.Receipt`: one payload builder per struct.
- Two payment-link pages, two receipt controllers, two confirmation emails and two payment-link emails.
- The monthly report (`TASK-11`) will have to sum both.

### The idea

A course is a product whose size is a seat. A booking is an order with one course line, quantity = seats. Holding seats while the customer pays becomes stock, which already has take and return on placing and cancelling. "Remove a seat" becomes editing the order's quantity, which already leaves a Balance to refund.

### What stands in the way

- **Fulfilment is mandatory on an order.** `place_custom` and checkout require a fulfilment option and date, a recipient phone for delivery, and so on. A course order has none. This needs fulfilment to become optional on an order, or a third method like `:none`. That's the main cost.
- **Seat holds have a timeout.** A pending booking holds seats while the customer pays (`holds_seats?`), and stock is only taken when an order is placed. Either stock gains a hold, or booking places the order first and pays after, as a Custom Order with a payment link does.
- **Checkout is a flower checkout.** Contact details, gift options and delivery steps don't apply. Course booking would keep its own short form that places the order directly.
- **Customer-facing copy** on the account page, emails and receipts says "booking" and shows the course date, place and time, not a fulfilment.
- **Data migration** of existing registrations and their payments.

### Recommendation

Not yet. Finish `TASK-17` first: it removes most of the duplication for a fraction of the risk. Revisit if:
- fulfilment becomes optional on orders for another reason (e.g. gift cards), or
- the monthly report turns out awkward with two sources.

### Open questions

- Is a course genuinely a sale like any other for the accountant, at the same VAT treatment as the order's lines? (It is today: `tax_rate` is on the booking.)
- Would Jennie want to sell a course seat over the counter as part of a Custom Order with flowers? If yes, that argues for this change.
<!-- SECTION:DESCRIPTION:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-18 14:18

---

Decided not worth implementing. TASK-17 removed most of the duplication; making fulfilment optional on orders, seat holds and migrating registrations cost more than the remaining duplication.

---
<!-- COMMENTS:END -->
