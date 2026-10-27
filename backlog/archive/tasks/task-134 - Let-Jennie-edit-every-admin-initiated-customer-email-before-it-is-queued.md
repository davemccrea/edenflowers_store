---
id: TASK-134
title: Let Jennie edit every admin-initiated customer email before it is queued
status: done
assignee: []
created_date: '2026-10-26 10:51'
updated_date: '2026-10-27 13:57'
labels:
  - spec
  - admin
  - customers
  - wontfix
dependencies: []
priority: medium
type: feature
ordinal: 261000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie can edit the generated subject and full plain-text body of any customer email she explicitly sends from the admin, and the final text is queued for delivery.

**Why:** The standard email wording is still evolving. Jennie needs to adjust complete messages herself rather than being limited to an optional note or requiring code changes for each wording adjustment. A consistent composer makes it clear what the customer will receive.

## Agreed direction
- Treat this as composing an email, not previewing a template. Start with the standard subject and body generated from the current record and customer language.
- Cover every admin-initiated customer email, including standalone Send email actions and optional emails accompanying another action, such as adding a booking, cancelling, recording payment or fulfilling an order. Inventory the real entry points before implementation rather than assuming they all use the shared component.
- Let Jennie edit both subject and body as ordinary text. Generated content follows form changes until she edits either email field; afterward preserve the draft, including when email sending is temporarily unticked.
- Provide Reset to standard email to deliberately regenerate both fields from the current details and customer language.
- Jennie is responsible for the accuracy of her edited wording. Do not add stale-information warnings or silently overwrite her edits after booking, order or payment details change.
- Keep recipients, sender, attachments and valid payment links system-managed. Never send the current dummy preview URL. Resolve any system-managed link placeholders against the saved record without otherwise rewriting her text.
- Queue the final subject and body together with the triggering action through the existing domain and background-delivery flow. Retries must retain the composed wording rather than regenerate it from a later template or changed record.
- Reuse one shared composer across admin send paths. This is not a rich-text editor, template editor, reusable-draft feature or cross-visit draft store. Edits affect only that send.

## Out of scope
Automatic emails, including website checkout messages, scheduled reminders and authentication codes, retain their existing generation and delivery behavior. Do not change the standard email wording as part of this feature.

## Triage remaining
This discussion established the product direction but has not undergone the repository grilling workflow. Before implementation, confirm the complete admin email inventory, required subject/body validation, and the exact system-managed link behavior when a draft is edited or payment terms change. Keep needs-triage until that review is complete.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every admin-initiated customer email entry point is inventoried and uses the shared editable subject/body composer, including emails accompanying other actions.
- [ ] #2 The initial subject and body match the standard customer-language email; automatic updates stop after Jennie edits either field, and her draft survives validation errors and temporarily disabling email sending.
- [ ] #3 Reset to standard email regenerates both fields from the current record/form details and customer language; no stale-information warnings are added.
- [ ] #4 Confirming a send queues the final composed subject and body; delivery and retries preserve that wording, apart from resolving system-managed links to valid saved-record URLs.
- [ ] #5 Recipients, sender and attachments retain existing behavior; dummy preview URLs cannot reach customers, and disabling optional email queues nothing.
- [ ] #6 Subject/body validation and send authorization are enforced in the domain, and tests cover composed delivery, retries, draft preservation/reset, optional-send behavior and real payment-link resolution.
- [ ] #7 Automatically triggered emails remain unchanged, and rendered standard emails are reviewed in Swedish, Finnish and English using mix print_emails.
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-27 13:57

---

Launch triage 2026-10-27 with David: closed. Too large for the gain: the optional note covers one-off wording, and standard wording changes are a code edit.

---
<!-- COMMENTS:END -->
