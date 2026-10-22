---
id: TASK-90
title: Open admin customer searches in the Fastmail iOS app
status: needs-info
assignee: []
created_date: '2026-10-22 07:08'
updated_date: '2026-10-22 07:11'
labels:
  - spec
  - admin
dependencies: []
priority: low
type: research
ordinal: 188000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Tapping a customer's email address in the admin on Jennie's iPhone shows her correspondence with them in the Fastmail app, not Safari.

**Why:** Jennie checks customer emails from her phone, and the app is where she reads mail. Safari works, but it takes her out of the app and needs her to stay signed in there.

Today (f67a7cdc), compose links open the app through `fastmail://mail/compose?...`. Search links open Fastmail web in Safari through `x-safari-https://`, because the app has no known link that opens a search:
- `app.fastmail.com` links open in Safari, not the app. Fastmail's site files don't let iOS hand them to the app.
- `fastmail://mail/search:<address>` and three variants (trailing slash, with host, `search?q=`) open the app on the inbox.

Waiting on Fastmail support: a draft asking whether any URL opens a search in the iOS app is in David's Fastmail Drafts (subject "Link to a search in the iOS app?"). Once they reply, switch `email_link`'s `data-app-href` (admin components.ex) to the URL they give, or archive this as wontfix if there isn't one.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The search link format Fastmail support gives opens a search for the address in the iOS app
- [ ] #2 Admin customer email links on a phone open that search in the Fastmail app
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-22 07:11

---

David sent the question to support@fastmail.com on 2026-10-22.

---
<!-- COMMENTS:END -->
