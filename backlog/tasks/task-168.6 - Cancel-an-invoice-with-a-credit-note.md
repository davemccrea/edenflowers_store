---
id: TASK-168.6
title: Cancel an invoice with a credit note
status: ready-for-agent
assignee: []
created_date: '2026-11-01 20:57'
labels: []
dependencies:
  - TASK-168.4
  - TASK-168.5
parent_task_id: TASK-168
type: feature
ordinal: 320000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** A sent invoice is in the customer's and the accountant's hands, so a mistake has to be undone with a document, not by editing it.

Cancelling a sent invoice issues a credit note (hyvityslasku) from the same number series. It names the original invoice and credits its amount. The credit note is rendered as a PDF and emailed like an invoice. A cancelled invoice no longer counts toward the amount invoiced, so the next invoice defaults to the right amount. A paid invoice can't be cancelled.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Cancelling an invoice issues a numbered credit note naming it
- [ ] #2 The credit note PDF and email go out in the invoice's language
- [ ] #3 Cancelled invoices don't count toward the amount already invoiced
- [ ] #4 A paid invoice can't be cancelled
<!-- AC:END -->
