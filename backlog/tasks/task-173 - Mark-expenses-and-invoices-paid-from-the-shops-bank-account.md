---
id: TASK-173
title: Mark expenses and invoices paid from the shop's bank account
status: done
assignee: []
created_date: '2026-11-04 17:44'
updated_date: '2026-11-04 18:32'
labels:
  - spec
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 331000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The shop's S-Pankki account, read through Enable Banking, marks expenses and invoices paid when a payment with a matching reference number books.

**Why:** Jennie schedules supplier invoices in her banking app and gets customer transfers there, then has to remember to mark each one paid in admin. Missed ones put an expense in the wrong VAT month or leave an invoice looking unpaid.

## Decisions

- **Bank access:** Enable Banking Production application in restricted mode (free, own linked accounts only). App ID and RS256 private key in the Ansible vault, passed as ENABLE_BANKING_APPLICATION_ID and ENABLE_BANKING_PRIVATE_KEY. JWT: kid = app ID, iss enablebanking.com, aud api.enablebanking.com, exp at most 24 h. S-Pankki (FI) allows 180-day consent.
- **Connection:** one stored bank session (session_id, accounts, valid_until). Connect/Reconnect from a status line at the top of the admin Expenses page ("Bank connected until 3 May"), via POST /auth with the longest allowed consent, back to /admin/bank/callback, POST /sessions. From 14 days before expiry the line turns into a warning. No email, no banner on other pages.
- **Sync:** AshOban scheduled action every 6 hours (PSD2 allows about 4 unattended reads a day). Does nothing without the Enable Banking env vars, which only production has, so dev and worktrees never touch the bank. Reads booked (BOOK) transactions since the connection, no backfill of older history. Failures raise; ErrorTracker alerts.
- **Matching:** by reference number only, compared without spaces. Card payments and transfers without a reference are left for Jennie.
- **Outgoing to expenses:** a matching unpaid expense is marked paid on the booking date only if the amount and currency also match to the cent. A mismatch stays unpaid. No stored bank transaction ID: a paid expense can't match again.
- **Incoming to invoices:** a matching issued, open invoice gets the transfer recorded through Invoice.record_payment with its amount and booking date, part payments included. An overpayment is left for Jennie: `record_payment` refuses more than is owed. No customer email, no notification to Jennie. The Payment stores the bank transaction ID so it's never recorded twice. Nothing in admin shows it came from the bank.
- **Scheduled expenses:** a separate change (59e72128) already lets Jennie mark a payment scheduled, as a future `paid_on`. The sync replaces that date with the booking date.
- **Dropped:** backfilling reference numbers onto existing expenses, renewal emails, 'from bank' notes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Jennie can connect and reconnect the S-Pankki account from the admin Expenses page, which shows until when it's connected
- [x] #2 A booked supplier payment whose reference number, amount and currency match an unpaid expense marks it paid on the booking date
- [x] #3 A booked customer transfer whose reference number matches an open invoice is recorded as its payment, once
- [x] #4 Dev and worktrees never call Enable Banking
<!-- AC:END -->
