---
id: TASK-116.4
title: Limit Brevo contact synchronisation to necessary data
status: needs-triage
assignee: []
created_date: '2026-10-26 18:57'
labels: []
dependencies: []
parent_task_id: TASK-116
type: task
ordinal: 265000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Customers should not acquire unnecessary purchase-statistics profiles in the email provider merely because they ordered flowers.

Review Accounts.Workers.SyncNewsletterList and Accounts.User.brevo_contacts against actual transactional SMS and newsletter-segmentation use. The current sync includes non-subscribers with phone numbers and sends order count, latest order date and total spent. Remove attributes/contacts with no necessary current purpose, preserving transactional emails, subscriber preferences and suppression behaviour.

Open before implementation: whether order SMS and purchase-based segmentation are actually used, the purpose/basis for retained fields, and how existing Brevo profiles should be minimised without removing suppression or resubscribing anyone. Do not assume deleting list membership deletes a contact or its attributes.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Every retained contact category and attribute has a confirmed current purpose and lawful basis; unused enrichment is removed.
- [ ] #2 Existing provider-held unnecessary data is handled explicitly and safely, not merely omitted from future upserts.
- [ ] #3 Tests preserve transactional delivery, newsletter opt-in/out, suppression and shared-phone behaviour; the notice matches the resulting sync.
<!-- AC:END -->
