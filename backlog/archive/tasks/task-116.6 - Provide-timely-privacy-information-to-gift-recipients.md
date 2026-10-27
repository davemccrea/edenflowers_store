---
id: TASK-116.6
title: Provide timely privacy information to gift recipients
status: done
assignee: []
created_date: '2026-10-26 18:57'
updated_date: '2026-10-27 13:57'
labels:
  - wontfix
dependencies: []
parent_task_id: TASK-116
type: task
ordinal: 267000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** People receiving flowers need to know how the shop uses the personal details supplied by the purchasing customer.

Design and implement Article 14 information for Recipients, including the source of their details and any delivery-photo disclosure to the Customer. Consider a short first-contact notice/link and delivery information, without adding Recipients to marketing lists. A public policy or instruction to the Customer alone does not establish compliance.

Open before implementation: available contact channels, when data first reaches HERE/Mapbox/other recipients, first-contact/disclosure timing, surprise-gift handling and any genuinely applicable exception. A delivery card alone may be too late; small size or gift surprise is not an automatic disproportionate-effort exception. Coordinate the public notice and readable customer-language versions; translations remain separately opt-in.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The approved design satisfies Article 14 timing or records a defensible applicable exception, including earlier communication/disclosure triggers.
- [ ] #2 Appropriate recipient-facing information identifies controller, purposes/bases, source, relevant sharing, retention and rights via a concise notice/link.
- [ ] #3 Tests cover relevant communication paths, Customer versus Recipient distinction and exclusion from marketing; email changes include previews and rendered review in each language.
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-27 13:57

---

Launch triage 2026-10-27 with David: closed. One sentence in the privacy policy says recipient details come from the person who ordered and are used only to deliver.

---
<!-- COMMENTS:END -->
