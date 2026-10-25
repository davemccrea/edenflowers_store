---
id: TASK-129
title: Use the same promotion-validity rule in checkout and newsletter emails
status: needs-triage
assignee: []
created_date: '2026-10-25 14:15'
labels:
  - spec
  - customers
  - developers
dependencies: []
references:
  - lib/edenflowers/pricing/promotion.ex
  - lib/edenflowers/pricing/workers/send_newsletter_promo_email.ex
  - test/edenflowers/pricing/workers/send_newsletter_promo_email_test.exs
priority: medium
type: bug
ordinal: 251000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Newsletter emails offer a promotion only when the same resource validity rule used by checkout says it is usable.

**Why:** The email worker maintains a narrower copy of validity rules, so an edited promotion can be withheld despite being usable or offered despite a future start date; removing expiration can also make the worker fail.

Review evidence: Promotion.:by_code supports optional start/expiration dates and usage < usage_limit (or unlimited). SendNewsletterPromoEmail.still_usable? instead requires usage == 0 and compares expiration_date directly, without allowing nil or checking start_date. Newsletter defaults normally mask these differences, but the resource permits edits to these fields.

Define validity once as a resource calculation and use it from both the by-code read and newsletter worker. Preserve Helsinki-day boundaries, inclusive date semantics and the existing welcome/already-subscribed email variants. Do not add another collection of special cases in the worker.

Triage confirms that admin-edited newsletter promotions follow the same validity semantics as checkout; no new promotion feature or email wording is requested.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A shared Promotion calculation expresses date and usage validity and is used by both the by-code read filter and newsletter email selection.
- [ ] #2 Optional expiration/start dates, future starts, inclusive expiration boundaries and finite/unlimited usage limits produce the same validity result for email and checkout.
- [ ] #3 The worker does not crash when expiration is nil and does not require zero usage when the actual usage limit permits reuse.
- [ ] #4 Regression tests cover the divergent edited-promotion cases while retaining existing newsletter email variants and normal one-use-code behaviour.
<!-- AC:END -->
