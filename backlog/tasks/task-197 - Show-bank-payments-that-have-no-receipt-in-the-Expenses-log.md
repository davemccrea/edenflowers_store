---
id: TASK-197
title: Show bank payments that have no receipt in the Expenses log
status: done
assignee: []
created_date: '2026-11-13 16:44'
labels:
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 362000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie needs to see which payments out of the shop's account have no invoice or receipt in Expenses, especially before sending the accountant the previous month's report.

## Decisions

- **Stored payments:** the 6-hourly bank sync keeps every booked outgoing payment as a `Bank.Transaction` (bank id, booking date, amount, currency, payee, message, reference). It stores nothing booked before the connection and does no backfill. Incoming payments aren't stored, and neither is a payment without a bank id.
- **Has its receipt:** a paid expense carries the payment's bank id (`Expense.bank_transaction_id`). That happens when the sync settled it, when it was auto-linked, or when Jennie linked it by hand.
- **Auto-link (card payments):** after each sync, every payment still awaiting a receipt links to an expense already paid by other means, with the same amount and currency, `paid_on` within ±7 days of the booking, not linked to another payment, and not unlinked from this payment. Payments go oldest first, each taking the earliest-paid expense. The expense's paid date doesn't change.
- **Missing list:** not dismissed, paying no paid expense, and booked over 7 days ago or in a month that has ended (on the 1st the whole previous month shows).
- **Expenses page:** a "Bank payments without a receipt" section with a count. "Link to expense" opens a picker of unlinked expenses dated within 30 days, closest amount first, in any currency. Linking marks an unpaid or scheduled expense paid on the booking date. "No receipt needed" dismisses a payment, and a collapsed "N dismissed" list has Restore.
- **Expense page:** a "Bank payment" widget with Unlink. Unlinking keeps the paid date, puts the payment back on the list and stores its id in `unlinked_bank_transaction_ids`, so that pair never auto-links again and the payment never settles another expense by amount.
- **Overview:** a "Bank payments without a receipt" group in Needs attention, linking to the Expenses section.
- **Dropped:** backfill, notifications, changes to the monthly report, payee rules.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Booked payments out are stored once, however often the sync reads them
- [x] #2 A card payment links to the already-paid receipt of its amount and currency within a week, keeping its paid date
- [x] #3 Payments without a receipt show on the Expenses page once over a week old or from an ended month, and on the Overview
- [x] #4 Jennie can link a payment to an expense by hand, which marks an unpaid one paid on the booking date
- [x] #5 Jennie can dismiss a payment as needing no receipt and restore it
- [x] #6 Unlinking on the expense page puts the payment back on the list and stops that pair linking again
<!-- AC:END -->
