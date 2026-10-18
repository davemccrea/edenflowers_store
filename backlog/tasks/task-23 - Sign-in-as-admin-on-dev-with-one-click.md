---
id: TASK-23
title: Prefill an admin's sign-in code on dev
status: done
assignee: []
created_date: '2026-10-18 05:42'
updated_date: '2026-10-18 12:10'
labels:
  - quick
  - spec
  - developers
dependencies: []
priority: low
type: chore
ordinal: 76000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Every DB reset means another OTP round trip through the dev mailbox to sign in as admin.

Signing in as admin on dev takes an OTP round trip (type email, open /dev/mailbox, copy code, paste), and every DB reset wipes the tokens table so it happens often. Make the code step prefilled for admins.

Build:
- In `SendOtp`, when `dev_routes` is on and the recipient is an admin, put the real code in the process dictionary. The sender runs in the `OtpSignInLive` process that requested it.
- `OtpSignInLive` takes it after a successful request (and resend) and prefills the code field.

Decisions:
- Dev only. Staging stays prod-like.
- Admins only, any admin email.
- No magic OTP code and no dev route: the real code goes through the real strategy; you still press Sign in.
- No automated test: `dev_routes` is off in test. Verify by hand in dev.
- Replaces the earlier one-click `/dev/sign-in-as-admin` route, which needed its own JWT minting and dev guards.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 In dev, requesting a code for an admin email lands on the code step with the code prefilled
- [x] #2 Non-admin emails get no prefill
- [x] #3 No prefill when dev_routes is off (staging, prod)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified in dev with Playwright: mail@dmccrea.me lands on the code step with the code prefilled, and pressing Sign in signs in. Non-admin case checked by reading the code only (match? on admin: true). MIX_ENV=prod compile is clean.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-18 05:46

---

Spec agreed in a grilling session.

---
<!-- COMMENTS:END -->
