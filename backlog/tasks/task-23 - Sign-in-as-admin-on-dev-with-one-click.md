---
id: TASK-23
title: Sign in as admin on dev with one click
status: ready-for-agent
assignee: []
created_date: '2026-10-18 05:42'
updated_date: '2026-10-18 11:24'
labels:
  - quick
  - spec
dependencies: []
priority: low
type: chore
ordinal: 76000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Every DB reset means another OTP round trip through the dev mailbox to sign in as admin.

Signing in as admin on dev takes an OTP round trip (type email, open /dev/mailbox, copy code, paste), and every DB reset wipes the tokens table so it happens often. Make it one click.

Build:
- `GET /dev/sign-in-as-admin` inside the existing `dev_routes` scope in the router, so it only compiles in dev (not staging, not prod).
- It loads the user `mail@dmccrea.me` and signs them in the same way `AuthController.success/4` does (`store_in_session`), then redirects to `return_to` from the session if set, otherwise `/admin`.
- If that user doesn't exist, redirect with a flash telling you to run the seeds.
- On the OTP sign-in page, show a "Sign in as admin (dev)" button linking to the route, rendered only when `Application.compile_env(:edenflowers, :dev_routes)` is true.

Decisions:
- Dev only. Staging stays prod-like.
- Admin only. Add a customer login when it's needed.
- No magic OTP code: keep the real auth strategy free of dev branches.
- No automated test: the route doesn't exist in the test env. Verify by hand in dev.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Visiting /dev/sign-in-as-admin in dev signs in mail@dmccrea.me and lands on /admin
- [ ] #2 If return_to is set in the session, the route redirects there instead of /admin
- [ ] #3 If mail@dmccrea.me doesn't exist, the route redirects with a flash saying to run the seeds
- [ ] #4 The OTP sign-in page shows a 'Sign in as admin (dev)' button in dev only
- [ ] #5 Neither the route nor the button exists when dev_routes is off (staging, prod)
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-18 05:46

---

Spec agreed in a grilling session.

---
<!-- COMMENTS:END -->
