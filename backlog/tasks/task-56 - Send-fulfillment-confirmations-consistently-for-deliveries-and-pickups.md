---
id: TASK-56
title: Send fulfillment confirmations consistently for deliveries and pickups
status: done
assignee: []
created_date: '2026-10-18 21:23'
updated_date: '2026-10-19 06:14'
labels:
  - spec
  - admin
  - customers
dependencies: []
priority: medium
type: feature
ordinal: 122000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Jennie can reliably email a fulfillment confirmation when marking either a delivery or a pickup fulfilled.

**Why:** The admin currently offers “Email the customer” for pickups, but the background job only sends delivery emails. Jennie cannot tell whether her choice will actually notify the customer.

## Problem Statement
The fulfillment form promises an email for both delivery and pickup, while the sending rule only permits deliveries. Sending is asynchronous, and immediate jobs and scheduled recovery must agree on eligibility. A separate empty-form crash for pickups without customer email was reproduced and fixed during the investigation; preserve that regression coverage.

## Solution
Use one fulfillment-confirmation flow with delivery or collection wording. Keep the existing background-job and recovery machinery, and make the admin controls accurately describe what will be sent.

## User Stories
1. As Jennie, I want an emailed delivery confirmation when I mark a delivery fulfilled, so the customer knows it arrived.
2. As Jennie, I want an emailed collection confirmation when I mark a pickup fulfilled, so the email checkbox works consistently.
3. As a customer, I want the subject and body to describe delivery or collection correctly.
4. As Jennie, I want to opt out of the confirmation, so the recovery scheduler does not later send an email I declined.
5. As Jennie, I want orders without an email address to be fulfillable without an email option or background email job.
6. As Jennie, I want to choose whether a left-at-door photo is emailed with the delivery confirmation.
7. As a customer, I want temporary sending or photo-service failures retried without receiving another confirmation after a successful send has been recorded.
8. As Jennie, I want fulfillment notifications to work regardless of whether an order is paid.

## Implementation Decisions
- Extend the existing delivery-email pipeline to fulfillments; do not introduce a separate pickup worker or scheduler.
- Use the same eligibility rule for immediate jobs and scheduled recovery, and recheck it when executing: order is placed, fulfilled, has a customer email, has no recorded successful fulfillment email, and sending was not explicitly skipped. Both delivery and pickup are eligible; payment status is irrelevant.
- Preserve the opt-out persistently so scheduled recovery respects it.
- Use delivery wording for deliveries and “Your order has been collected” wording for pickups, in subject and body. Preserve customer-locale rendering and existing sender/Bcc behaviour.
- Label the checkbox “Email delivery confirmation” or “Email collection confirmation”; hide it when there is no customer email. Default it to checked each time the form opens.
- Offer “Email the photo” only for a left-at-door delivery when customer emailing is enabled. Disabling customer emailing must prevent any photo email.
- Retain the existing retry policy and ten-minute recovery schedule. If an opted-in photo cannot be fetched or resized, fail and retry the email rather than silently omitting the photo. Only record sent status after successful mailer delivery.
- Reuse the existing sent timestamp and opt-out state; avoid schema churn solely for terminology. Rename delivery-specific code/history wording where it would otherwise misdescribe pickup confirmations, preserving existing recorded state and queued-job compatibility.

## Testing Decisions
Use the existing admin order-detail LiveView tests for the actual confirmation-form interactions and the existing order/email job tests for executing queued sends. Assert customer-visible subjects/bodies, recorded sent status, opt-out behaviour, and eligibility rather than only job insertion. Cover delivery, pickup, no email, unpaid orders, photo selection/failure, scheduled recovery, and repeat execution after successful sending.

## Out of Scope
Changing the email provider, receipt/payment emails, pickup-ready notifications, introducing new notification infrastructure, or guaranteeing exactly-once delivery across an SMTP-success/database-failure boundary.

## Further Notes
Follow-up to TASK-54 and the error reported at http://localhost:4000/admin/errors/1. Development uses the local Swoosh mailbox; tests should not depend on real inbox delivery.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A fulfilled delivery or pickup with customer email and sending enabled receives a confirmation with correct delivery/collection subject and body in the customer locale.
- [x] #2 The checkbox accurately names delivery/collection confirmation, defaults to checked on opening, and is absent when there is no email; no-email pickups can still be fulfilled.
- [x] #3 Opting out prevents immediate and scheduled sending, and unpaid placed orders remain eligible when sending is enabled.
- [x] #4 Immediate sending and scheduled recovery use the same eligibility conditions and recheck them during execution; a recorded successful send is not sent again.
- [x] #5 Left-at-door photo emailing is offered only while customer emailing is enabled; opted-in photo failures remain retryable and do not record the email as sent.
- [x] #6 Existing retry/recovery behaviour, sent/skip state, sender/Bcc behaviour, and queued-job compatibility are preserved, with regression coverage through the existing form and email-job seams.
- [x] #7 The admin shows domain-derived confirmation email status and why sending is skipped, delayed or unsuccessful, with safe retry for eligible unsent confirmations.
- [x] #8 The fulfillment form shows the email destination, nests Include the delivery photo under the confirmation choice, explains missing email addresses, and reports fulfillment and email outcomes separately.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented one explicit fulfillment-email eligibility expression in the Order domain, shared by immediate queueing, scheduled recovery and the sending action. Delivery and pickup use one customer-localized confirmation pipeline, with product-neutral order wording and an optional attached delivery photo. Existing worker/action names, retry schedule and database fields remain compatible.

The admin uses the existing native right drawer for fulfillment confirmation, with destination/no-address explanations, nested photo emailing and inline validation. Domain-derived email status and eligible retry remain visible on the order page and update without resetting in-progress forms. Retry atomically expedites only retryable jobs and uses native uniqueness for replacements.

Pre-commit review found and fixed stale-struct eligibility bypass and native drawer dismissal retaining a photo. The sending action now refetches and locks the current order in a transaction before checking eligibility; no-op sends do not create false sent-history entries. Opening a fresh drawer forgets prior uploads. Regression tests reproduced all findings before the fixes.

Verification: mix precommit passed with 1376 tests, 0 failures, plus compilation with warnings as errors, formatting, strict Credo and Ash codegen checks. Translation extraction freshness and diff checks passed. Swedish/Finnish translations are active without fuzzy flags.

Rollout behaviour follows the spec: recovery also includes already-fulfilled pickups with email and no recorded successful send or opt-out, so historical catch-up confirmations may be sent.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-18 21:37

---

Follow-up wording change: fulfillment confirmations now refer to the order rather than flowers, including gift deliveries, left-at-door photo emails, and admin photo labels/errors. Pickup already used order wording. Both relevant test files pass (58 tests); formatting and diff checks pass. New wording remains translatable; translation generation awaits opt-in.

---

author: @claude
created: 2026-10-18 21:42

---

Translations completed and activated (not fuzzy), following user preference. Swedish and Finnish cover the confirmation subjects/bodies, gift and left-at-door variants, photo labels/errors, checkbox labels and history entry, all using order rather than flowers. Newly extracted customer-selector strings were completed as well. English catalog entries were corrected to remove erroneous fuzzy matches. No missing or fuzzy entries remain in Swedish/Finnish default catalogs. Extraction freshness check, warnings-as-errors compilation, and both relevant test files passed (58 tests), including actual Swedish and Finnish pickup-email subjects/bodies.

---

author: @claude
created: 2026-10-18 21:44

---

User approved the UX follow-up: persistent confirmation-email status, explicit destination/no-address explanation, nested photo option, accurate completion feedback, and retry for delayed emails. Keep status interpretation and retry eligibility in the Orders domain. Translation preference remains active translations without fuzzy flags.

---

author: @claude
created: 2026-10-18 21:55

---

User selected the existing right-drawer pattern for fulfillment confirmation. Keep the status/retry controls on the order page. The drawer uses the native dialog component, scrollable form content and a fixed action footer; validation errors are rendered inside the drawer.

---

author: @claude
created: 2026-10-19 06:05

---

Completed the approved UX follow-up. Fulfillment confirmation uses the existing native right drawer with scrollable content, a fixed action footer and inline validation. Email destination/no-address explanations and nested Include the delivery photo clarify what will happen. The order page keeps a live domain-derived confirmation status and eligible retry action, and refreshes the history without resetting forms. Retry expedites only retryable jobs and uses AshOban uniqueness for replacements, so discarded jobs are not revived alongside recovery jobs. Photo errors have a stable delivery_photo_slug field marker for domain categorization; generic sending failures link to error details. Swedish/Finnish translations are active without fuzzy flags. Final checks: 1373 tests passed; warnings-as-errors compilation, formatting, strict Credo, Ash codegen, extraction freshness and diff whitespace checks passed. Native drawer behavior reuses the existing component; LiveView regressions cover drawer-open events, inline errors, asynchronous sent status and retry/recovery uniqueness.

---

author: @claude
created: 2026-10-19 06:14

---

Pre-commit double-check completed: fixed stale-record send/opt-out bypass with the native Ash refetch-and-row-lock change, suppressed no-op sent-history entries, and cleared old photos whenever the fulfillment drawer reopens. All 1376 tests pass via mix precommit.

---
<!-- COMMENTS:END -->
