---
id: TASK-116.4
title: Sync only newsletter subscribers to Brevo
status: done
assignee: []
created_date: '2026-10-26 18:57'
updated_date: '2026-10-29 07:25'
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
- [x] #1 brevo_contacts returns only users with newsletter_opt_in, and the sync no longer upserts non-subscribers
- [x] #2 Sync tests still cover opt-in, opt-out, blocklist and shared-phone behaviour
- [x] #3 Existing non-subscriber contacts are deleted from Brevo (human step)
- [x] #4 The privacy policy describes Brevo as holding newsletter subscribers only
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
brevo_contacts filters on newsletter_opt_in only; SyncNewsletterList dropped upsert_customers. Tests: a phone-number customer who never opted in is not sent; shared-phone test now uses a subscriber. Privacy page Brevo line rewritten (en/sv/fi).
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-27 14:07

---

Left for David: in Brevo, delete the existing contacts that are not on the newsletter list (they were synced as phone-number customers), then check AC #3 and set done.

---

author: @claude
created: 2026-10-29 07:25

---

David removed the non-subscriber contacts from Brevo.

---
<!-- COMMENTS:END -->
