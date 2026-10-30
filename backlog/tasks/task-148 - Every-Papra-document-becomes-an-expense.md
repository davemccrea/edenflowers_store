---
id: TASK-148
title: Every Papra document becomes an expense
status: ready-for-human
assignee: []
created_date: '2026-10-30 14:00'
labels:
  - spec
  - admin
dependencies: []
priority: medium
type: refactor
ordinal: 281000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Papra fires the expense import on `document:created` instead of the `receipt` tag, so uploading a PDF to Papra, by hand or from an invoice email, is the only step.

**Why:** Email imports and hand uploads ended up tagged differently in Papra (`receipt` on some, not others), and the tags only existed to fire the webhook. One trigger gives one pipeline and less code to keep right.

## Decisions

- The Papra organization holds only receipts and invoices, so every created document is an expense.
- No tags at all. The rename to `<date> <vendor>.pdf` shows a document is processed; one under its original name is pending or failed.
- The invoice email import only uploads; the webhook records it like any other upload.
- Deleting an expense no longer touches Papra. To re-import, delete the document in Papra and upload the PDF again: Papra restores it from the trash and fires `document:created` again.
- A missed webhook loses the document, as it already could for hand uploads.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Uploading a PDF to Papra creates an expense in admin without tagging it
- [ ] #2 An invoice email filed in Fakturor becomes an expense through the same webhook
- [x] #3 Deleting an expense doesn't depend on Papra being reachable
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-30 14:00

---

Code is in. Left for David: in Papra, add `document:created` to the webhook's events before deploying, so nothing uploaded around the deploy is missed, and remove `document:tag:added` after. Delete the `receipt` and `processed` tags, and drop `tags:read` from the API key. Then upload a PDF by hand and confirm it becomes an expense (AC #1), and that a filed invoice email does too (AC #2).

---
<!-- COMMENTS:END -->
