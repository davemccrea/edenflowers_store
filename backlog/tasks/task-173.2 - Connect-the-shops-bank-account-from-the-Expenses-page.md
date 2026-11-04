---
id: TASK-173.2
title: Connect the shop's bank account from the Expenses page
status: done
assignee: []
created_date: '2026-11-04 17:44'
updated_date: '2026-11-04 17:56'
labels: []
dependencies: []
parent_task_id: TASK-173
type: feature
ordinal: 333000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** the sync needs a bank consent, and only Jennie can give it by logging in to S-Pankki, again every 180 days.

- External.EnableBankingAPI with Req: RS256 JWT from the app ID and private key; POST /auth, POST /sessions, GET /accounts/{id}/transactions with continuation_key paging. Tests stub it with Req.Test, as FastmailAPI does.
- A one-row resource for the bank session: session_id, account ids, valid_until, connected_at. Reconnecting replaces it.
- Status line at the top of the admin Expenses page: not connected, connected until <date>, or a warning from 14 days before expiry. Connect/Reconnect starts POST /auth (S-Pankki, FI, longest consent GET /aspsps allows) with a signed state, then /admin/bank/callback swaps the code for a session.
- Copy through gettext in en, fi and sv.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Connecting from the Expenses page stores the session and shows its expiry date
- [x] #2 The status line warns from 14 days before the consent ends
- [x] #3 A callback with a wrong state or failed code stores nothing and shows an error
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Edenflowers.Bank domain with Bank.Connection (newest row is current; expired and renewal_due calcs). External.EnableBankingAPI signs RS256 JWTs with JOSE; GET /aspsps for the longest consent, POST /auth (psu_type business), POST /sessions. Connect/Reconnect on the Expenses page status line; BankController.callback verifies a Phoenix.Token state for the same admin. Hidden where Enable Banking isn't configured. Tests stub with Req.Test using a throwaway key in test/support/fixtures.
<!-- SECTION:NOTES:END -->
