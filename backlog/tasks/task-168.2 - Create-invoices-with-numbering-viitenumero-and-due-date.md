---
id: TASK-168.2
title: 'Create invoices with numbering, viitenumero and due date'
status: ready-for-agent
assignee: []
created_date: '2026-11-01 20:57'
updated_date: '2026-11-01 20:57'
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

Add Invoice, Credit note and Business customer to CONTEXT.md, and drop "Zervant invoice" from the Payment entry.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An invoice can only be created for a purchase on invoice terms with complete buyer details
- [ ] #2 Numbers are sequential with no gaps, starting after Zervant's last number
- [ ] #3 The viitenumero passes the Finnish check-digit rule
- [ ] #4 The amount defaults to the Balance not yet invoiced; the due date defaults to 14 days
- [ ] #5 Buyer details are copied onto the invoice and don't follow later edits
- [ ] #6 CONTEXT.md defines Invoice, Credit note and Business customer
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-01 20:57

---

Needs Zervant's last invoice number from David or Jennie before go-live; the agent can build with a placeholder in config.

---
<!-- COMMENTS:END -->
