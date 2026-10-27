---
id: TASK-124
title: Enforce email-change verification in Accounts actions rather than AccountLive
status: done
assignee: []
created_date: '2026-10-25 14:15'
updated_date: '2026-10-25 15:11'
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
- [x] #1 A direct ordinary-user call cannot change an email without valid proof tied to that user and destination address; no page-only convention is required.
- [x] #2 Request and confirmation actions enforce expiry, attempt and request limits, ownership/authorization, and email validation; successful proof cannot be reused to change to another address.
- [x] #3 AccountLive calls the domain actions and renders their results, without owning verification policy or directly enqueueing the verification email.
- [x] #4 Domain tests cover missing/wrong/expired proof, attempt exhaustion, successful confirmation and unauthorized use; existing account-page behaviour remains covered.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Triage decisions: kept 6-digit codes for consistency with OTP sign-in. AshAuthentication's confirmation add-on was considered and rejected for now: link-only, reveals taken addresses at request time, and needs confirmed_at plus disabling hijack protection. Pending change lives on users (pending_email, HMAC-SHA256 hash of the code keyed with token_signing_secret, expiry 10 min); a new request replaces the old one. Wrong codes are capped by AshRateLimiter on :confirm_email_change (5 per 10 min, counted before the transaction, since a failed confirm rolls back its own writes), the same approach as OTP sign-in. Requests: 5 per 15 min per user. Uniqueness is only checked at confirm. :change_email removed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
User.:request_email_change stores a hashed code and enqueues SendEmailChangeCode; User.:confirm_email_change locks and reloads the row, checks expiry and code, moves pending_email into email and clears it. AccountLive only submits and maps errors to messages.
<!-- SECTION:FINAL_SUMMARY:END -->
