---
id: TASK-168.2
title: 'Create invoices with numbering, viitenumero and due date'
status: done
assignee: []
created_date: '2026-11-01 20:57'
updated_date: '2026-11-01 21:34'
labels: []
dependencies:
  - TASK-168.1
parent_task_id: TASK-168
type: feature
ordinal: 316000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Everything else hangs off an invoice record whose number, amount and buyer never change after it's made.

Add an Invoice resource belonging to an order or a Course booking. Create action: allowed only on invoice terms and once buyer details are complete (consumer: name and email; business: the TASK-168.1 calculation). Number from one sequence continuing Zervant's (the starting number is set once, from config or a migration-safe seed). The viitenumero comes from the number with the Finnish check digit. The invoice date is today, the due date defaults to 14 days later and can be changed. The amount defaults to the Balance not yet invoiced. Locale defaults to the purchase's. Buyer details are frozen onto the invoice. Shop seller details (name, Y-tunnus, address, IBAN, BIC) go in config.

Also (agreed in the TASK-168.1 handoff): an update_business_details action on orders and Course bookings that changes only the five business fields, whatever the fulfilment status (cancelled included), so details can be added after delivery or to an existing booking. No UI here; TASK-168.4 builds it.

Add Invoice, Credit note and Business customer to CONTEXT.md, and drop "Zervant invoice" from the Payment entry.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 An invoice can only be created for a purchase on invoice terms with complete buyer details
- [x] #2 Numbers are sequential with no gaps, starting after Zervant's last number
- [x] #3 The viitenumero passes the Finnish check-digit rule
- [x] #4 The amount defaults to the Balance not yet invoiced; the due date defaults to 14 days
- [x] #5 Buyer details are copied onto the invoice and don't follow later edits
- [x] #6 CONTEXT.md defines Invoice, Credit note and Business customer
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Payments.Invoice (create/read only, immutable) with Changes.IssueInvoice and Validations.Invoiceable; fragment Payments.Invoiceable (invoiceable?, uninvoiced_balance, open_invoices_amount) and update_business_details on Order and CourseRegistration. Numbers: last + 1 under a transaction advisory lock; the first from config :invoices first_number (PLACEHOLDER 1000: needs Zervant's last + 1 before go-live, and must be at least 100 for a valid viitenumero). Viitenumero via Payments.ReferenceNumber, checked against Finance Finland's worked example. Seller details in config :invoices seller (IBAN and BIC are placeholders). Cancelled purchases can be invoiced, to bill what Jennie kept.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-01 20:57

---

Needs Zervant's last invoice number from David or Jennie before go-live; the agent can build with a placeholder in config.

---
<!-- COMMENTS:END -->
