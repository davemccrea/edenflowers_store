---
id: TASK-146
title: Import invoice emails from Fastmail into expenses
status: ready-for-human
assignee: []
created_date: '2026-10-30 09:13'
updated_date: '2026-10-30 10:11'
labels:
  - spec
  - admin
dependencies: []
priority: medium
type: feature
ordinal: 280000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Invoice emails Jennie files into the Fastmail folder `Fakturor` become expenses without anyone uploading them to Papra.

**Why:** Recurring bills like Hetzner's arrive by email every month and only reach the books if someone downloads the PDF and tags it in Papra. Polling the mailbox removes that chore and stops monthly bills being missed.

A Fastmail filter moves invoice emails (Hetzner first) into `Fakturor`; any invoice email can also be dragged there by hand. Papra's own intake emails were rejected because they need a relay or an open port 25.

## Decisions

- An AshOban scheduled action in `Expenses` polls every 15 minutes over JMAP with `Req` (no IMAP dependency, no sidecar). It does nothing unless `FASTMAIL_API_TOKEN` is set, which only prod has (Ansible vault): dev and worktrees point at production Papra and must never touch the mailbox.
- For each email in `Fakturor`, every PDF attachment is uploaded to Papra as its own document and recorded straight away with `record_expense_import`. No `receipt` tag: it only exists to fire the webhook. Emails without a PDF are left in `Fakturor` silently.
- Once all its PDFs are uploaded, the email moves to `Fakturor/Importerade`. The move plus Papra's per-organization hash dedupe (`409 document.already_exists`) are the only import record; no new table. A 409 counts as imported but is logged at error level, so the rare case of an upload whose import failed to save alerts and Jennie can tag it `receipt` by hand.
- Missing folders, login failures and Papra errors raise; ErrorTracker's existing alert emails once per distinct error.
- Tests stub Fastmail with `Req.Test` via `fastmail_req_options`; Papra gains an `upload_document` callback.
- Fastmail API token needs mail write access (to move). Papra API key needs `documents:create`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An invoice email moved into the Fastmail folder becomes an expense in admin without manual Papra uploads
- [x] #2 The same email is never imported twice, including after a failed or retried job
- [x] #3 Emails without a PDF attachment are skipped and left in the folder for Jennie to handle
- [x] #4 A failing mailbox login or Papra upload surfaces through the app's existing error alerts
- [x] #5 README's Papra expense capture section explains the folder and the Fastmail filter
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. PapraAPI.upload_document (multipart POST /documents).
2. External.FastmailAPI: JMAP session, Mailbox/get, Email/query+get with attachments, blob download, Email/set mailboxIds.
3. Expenses.ImportInvoiceEmails scheduled generic action, token guard.
4. Config (runtime, test), vault example, compose template, README.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ExpenseImport.import_invoice_emails runs every 15 min (Edenflowers.Expenses.Actions.ImportInvoiceEmails, Edenflowers.External.FastmailAPI). No-op without FASTMAIL_API_TOKEN. Papra 409 duplicate is logged at error level and counts as imported.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-30 10:11

---

Code is in. Left for David: create a Fastmail API token with mail write access and add vault_fastmail_api_token to the Ansible vault (provisioning fails without it); add documents:create to the Papra API key; create Fakturor and Fakturor/Importerade plus the Hetzner filter; provision and deploy, then confirm a filed Hetzner email becomes an expense (AC #1).

---
<!-- COMMENTS:END -->
