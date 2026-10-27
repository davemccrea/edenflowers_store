---
id: TASK-116.4
title: Sync only newsletter subscribers to Brevo
status: ready-for-agent
assignee: []
created_date: '2026-10-26 18:57'
updated_date: '2026-10-27 13:58'
labels:
  - launch
  - quick
dependencies: []
parent_task_id: TASK-116
type: task
ordinal: 265000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Customers who never signed up for the newsletter should not have a purchase profile (order count, last order date, total spent) in Brevo just because they gave a phone number at checkout.

Decided in launch triage (2026-10-27): Brevo holds newsletter subscribers only.

- `User.brevo_contacts` filters on `newsletter_opt_in` alone and its description drops the order-texts reason. Order texts through Brevo (TASK-80) are closed, and Brevo transactional SMS would only need the order's number anyway.
- `SyncNewsletterList` loses `upsert_customers` and the moduledoc paragraph about phone-number customers. Subscribers keep their attributes; they consented to marketing.
- One-off human cleanup: in Brevo, delete the contacts that are not on the newsletter list. Prod has had few real customers, so this is minutes in the UI.
- The privacy policy says Brevo holds newsletter subscribers (and sends transactional email).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 brevo_contacts returns only users with newsletter_opt_in, and the sync no longer upserts non-subscribers
- [ ] #2 Sync tests still cover opt-in, opt-out, blocklist and shared-phone behaviour
- [ ] #3 Existing non-subscriber contacts are deleted from Brevo (human step)
- [ ] #4 The privacy policy describes Brevo as holding newsletter subscribers only
<!-- AC:END -->
