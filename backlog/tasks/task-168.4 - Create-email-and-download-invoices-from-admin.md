---
id: TASK-168.4
title: 'Create, email and download invoices from admin'
status: ready-for-agent
assignee: []
created_date: '2026-11-01 20:57'
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
- [ ] #1 Jennie can create and send an invoice from an order or Course booking page
- [ ] #2 The customer gets an email with the PDF attached in the invoice's language
- [ ] #3 Admin lists the purchase's invoices with downloads
- [ ] #4 Missing business details are named in the form instead of failing silently
<!-- AC:END -->
