---
id: TASK-124
title: Enforce email-change verification in Accounts actions rather than AccountLive
status: needs-triage
assignee: []
created_date: '2026-10-25 14:15'
labels:
  - spec
  - customers
  - developers
dependencies: []
references:
  - lib/edenflowers/accounts/user.ex
  - lib/edenflowers_web/features/account/account_live.ex
  - test/edenflowers_web/features/account/account_live_test.exs
priority: high
type: bug
ordinal: 246000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
An account email can change only after the Accounts domain verifies ownership of the new address.

**Why:** Email is the sign-in identity. Today the page verifies a code, but Accounts.change_email accepts the new address without that proof, so another caller can bypass the intended invariant.

Review evidence: AccountLive generates and emails the code, stores expiry and attempts in socket assigns, and checks it before calling the action. User.:change_email only accepts email; the own-user update policy does not require verification. This is a missing domain guarantee, not a demonstrated browser-accessible exploit.

Move requesting and confirming an email change behind specific Accounts resource actions. The confirmation action must enforce the proof, address/user binding, expiry and attempt limit; AccountLive should only submit inputs and display outcomes. Preserve rate limits, secure code handling, uniqueness and the existing queued-email pattern. Reuse AshAuthentication facilities if suitable rather than building a second authentication framework.

Triage: settle the smallest verification mechanism and its lifecycle before implementation. Do not simply move the page code into a helper or leave an ordinary-user action that accepts an unverified address. Related architecture work: TASK-121, but this identity invariant is an independent deliverable.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A direct ordinary-user call cannot change an email without valid proof tied to that user and destination address; no page-only convention is required.
- [ ] #2 Request and confirmation actions enforce expiry, attempt and request limits, ownership/authorization, and email validation; successful proof cannot be reused to change to another address.
- [ ] #3 AccountLive calls the domain actions and renders their results, without owning verification policy or directly enqueueing the verification email.
- [ ] #4 Domain tests cover missing/wrong/expired proof, attempt exhaustion, successful confirmation and unauthorized use; existing account-page behaviour remains covered.
<!-- AC:END -->
