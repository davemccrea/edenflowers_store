---
id: TASK-116.3
title: Enforce category-specific customer-data retention
status: needs-triage
assignee: []
created_date: '2026-10-26 18:57'
labels: []
dependencies: []
parent_task_id: TASK-116
type: task
ordinal: 264000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The shop must stop retaining delivery-only and inactive customer data indefinitely without damaging its accounting records.

Implement the retention/minimisation outcome described in docs/research/privacy-policy-legal-review.md. Keep the financial core required by ADR-0004; cover customer identities, subscriptions, abandoned checkouts, unconverted enquiries and change histories, with mailbox/provider/job/log/backup copies explicitly accounted for. Delivery-photo deletion remains TASK-116.2 rather than a duplicate implementation here.

Open before implementation: accountant-approved record classification and applicable six-/ten-year minima; business-approved expiry periods and triggers; manual versus automatic handling; unresolved-payment, legal-hold and restore safeguards. Suggested periods in the review are proposals, not approved deletion authority. No production data changes without a separate authorised rollout and backup.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An approved category-specific schedule distinguishes statutory accounting records from delivery-only and inactive data, including copies and exceptions.
- [ ] #2 Retention is enforced through appropriate Ash actions/jobs or an explicit scheduled manual procedure, without deleting required purchase/payment history or disrupting reconciliation.
- [ ] #3 Tests cover boundaries, histories, retries and financial integrity; backup restoration does not silently reintroduce erased data.
- [ ] #4 The notice describes verified behaviour rather than intended or unimplemented expiry.
<!-- AC:END -->
