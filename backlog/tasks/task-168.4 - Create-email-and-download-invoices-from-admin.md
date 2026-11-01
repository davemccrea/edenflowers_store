---
id: TASK-168.4
title: 'Create, email and download invoices from admin'
status: done
assignee: []
created_date: '2026-11-01 20:57'
updated_date: '2026-11-01 22:29'
labels: []
dependencies:
  - TASK-168.3
parent_task_id: TASK-168
type: feature
ordinal: 318000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** This is the step that replaces opening Zervant: Jennie invoices from the order or booking page she's already on.

On the admin order and booking pages, add a "Create invoice" form (amount, due date, language, prefilled) that explains what's missing when buyer details are incomplete. List the purchase's invoices with download links. Sending emails the customer an Invoice email with the PDF attached, in the invoice's language. Add the email to `Edenflowers.Email.Previews` and `docs/agents/email-map.md`, and review it with `mix print_emails`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Jennie can create and send an invoice from an order or Course booking page
- [x] #2 The customer gets an email with the PDF attached in the invoice's language
- [x] #3 Admin lists the purchase's invoices with downloads
- [x] #4 Missing business details are named in the form instead of failing silently
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Invoice gains sent_at and a :send update (Changes.SendInvoice: PDF first, then the Invoice email in the invoice's locale, Jennie's message, stamps sent_at). Create takes email_customer? (default false; the admin form ticks it) and message; Changes.SendNewInvoice runs :send after commit, :emailed? metadata, so a failed email keeps the invoice and its number. One step by default (Create and send), two if unticked: the list's Send opens the drawer for it. Admin: InvoiceDrawer live component (create, business details via update_business_details, send) and invoice_list on the order page (Invoices widget) and course page (under each booking; Create invoice in its menu). BusinessCustomer.missing_business_details names what's missing. GET /admin/invoices/:id (admin only) opens the PDF as lasku-/faktura-/invoice-N.pdf (InvoicePdf.filename/attachment). update_business_details is in the order log as Business details changed. Email: part-of-total line only when the amount is below the Balance. fi/sv copy AI-drafted, queued as T21. Cancelled bookings have no menu, so no Create invoice there yet.
<!-- SECTION:NOTES:END -->
