---
id: TASK-116.5
title: Audit Stripe browser storage and implement the required consent behaviour
status: needs-triage
assignee: []
created_date: '2026-10-26 18:57'
labels: []
dependencies: []
parent_task_id: TASK-116
type: task
ordinal: 266000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Shoppers must not receive non-exempt cookies or device tracking before consent, while necessary payment security continues to work.

Audit live Stripe/session/Cloudflare browser cookies, storage and device access, purposes, recipients and lifetimes. Stripe.js currently loads site-wide with optional advanced fraud signals not disabled. Assess Finnish Electronic Communications Services Act section 205 and GDPR separately. Prefer removing unnecessary site-wide/optional processing where appropriate; only implement a consent mechanism if retained non-exempt processing needs it.

Open before implementation: observed live behaviour, which fraud/security features are necessary, effect of restricting Stripe loading/signals, and Stripe Radar decision settings. Neither restricting loading nor disabling advanced signals alone proves consent is unnecessary. Provider dashboard/browser checks require human confirmation where agent access is unavailable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A browser-backed inventory and necessity/consent assessment covers initial visits, cart, payment and sign-in.
- [ ] #2 Chosen loading/security controls preserve payment functionality; any non-exempt processing is gated by prior consent with practical rejection and withdrawal.
- [ ] #3 Tests verify relevant loading/consent boundaries and payment regressions; policy wording and any significant automated-decision disclosure match verified settings.
<!-- AC:END -->
