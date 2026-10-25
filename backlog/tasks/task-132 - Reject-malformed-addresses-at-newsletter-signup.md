---
id: TASK-132
title: Reject malformed addresses at newsletter signup
status: needs-triage
assignee: []
created_date: '2026-10-25 16:49'
labels:
  - spec
  - customers
dependencies: []
priority: low
type: bug
ordinal: 254000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
A footer signup with a malformed address is turned away instead of being saved and promised a code.

**Why:** User.email is a plain :ci_string, so :subscribe_to_newsletter accepts any non-empty text (e.g. "not an email"). The footer then promises a 15% code, the queued welcome email can't be delivered, and the junk row is synced to Brevo as a subscriber. Checkout and email change already validate with Edenflowers.Types.Email; the footer is the gap (the browser's type=email check is the only guard).

Open for triage:
- Validate on User.email itself (an Edenflowers.Types.Email that keeps case-insensitive matching) or only on the :subscribe_to_newsletter / :upsert actions.
- Whether production already holds malformed rows, and what to do with them (check, then fix or leave).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Submitting a malformed address in the footer shows the inline error, records no user and queues no email
- [ ] #2 Valid addresses still match existing users case-insensitively
- [ ] #3 Any malformed rows already in production are accounted for
<!-- AC:END -->
