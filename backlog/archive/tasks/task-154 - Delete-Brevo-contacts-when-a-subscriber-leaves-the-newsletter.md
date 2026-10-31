---
id: TASK-154
title: Delete Brevo contacts when a subscriber leaves the newsletter
status: done
assignee: []
created_date: '2026-10-31 07:38'
updated_date: '2026-10-31 07:40'
labels:
  - spec
  - customers
  - wontfix
dependencies: []
priority: medium
type: bug
ordinal: 287000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When someone leaves the newsletter, their Brevo contact is deleted, so Brevo only ever holds current subscribers.

**Why:** The privacy policy says Brevo holds newsletter subscribers only, but `SyncNewsletterList` only removes leavers from the list (`/contacts/lists/:id/contacts/remove`). Their contact stays in Brevo with name, phone, order count and total spent.

Decided so far (2026-10-31):
- Opted out in the app (or never opted in but left on the list): delete the contact.
- Unsubscribed in Brevo (blocklisted): keep the contact so the blocklist keeps suppressing campaigns, but strip its attributes.

Seen in prod Brevo on 2026-10-31: 3 contacts, 1 on the newsletter list. One off-list contact (created 2026-10-25, before TASK-116.4 landed) still has purchase attributes and no LANGUAGE, so it is probably a non-subscriber left over from before TASK-116.4 rather than an opt-out. TASK-116.4's manual cleanup seems to have missed it.

Open: whether the sync should also delete any off-list contact it finds (catching leftovers like the one above), or only contacts it removes itself.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A user who opts out in the app has no Brevo contact after the next sync
- [ ] #2 A user who unsubscribed in Brevo stays blocklisted in Brevo with no attributes
- [ ] #3 Sync tests cover both cases
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-31 07:40

---

Closed by David without implementing.

---
<!-- COMMENTS:END -->
