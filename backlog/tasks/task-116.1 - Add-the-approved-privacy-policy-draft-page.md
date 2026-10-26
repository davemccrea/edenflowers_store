---
id: TASK-116.1
title: Add the approved privacy-policy draft page
status: done
assignee: []
created_date: '2026-10-26 16:39'
updated_date: '2026-10-26 19:14'
labels:
  - quick
dependencies: []
parent_task_id: TASK-116
type: task
ordinal: 262000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** David wants the agreed privacy-policy text available as a clearly marked draft while retention and international-transfer decisions remain open.

Approved in this conversation: controller Jennie McCrea, trading as Eden Flowers; main customer database hosted by Hetzner in Finland. Add the agreed concise draft using the Terms page layout, with visible unresolved retention, transfers and recipient details. Expose language-prefixed routes with translatable English source text and links from the footer and signup/checkout. Do not invent legal retention periods or claim every service operates only in the EU. Keep the incomplete draft out of the sitemap and mark it noindex. Translation generation remains opt-in.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The privacy page identifies Jennie McCrea and Hetzner in Finland, contains the approved policy text and is visibly a draft with unresolved details.
- [x] #2 Language-prefixed routes, section navigation, alternate links and footer/newsletter/checkout links work.
- [x] #3 The draft is noindex and absent from the sitemap; focused tests pass.
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented PrivacyLive with the Terms page section-index layout and the agreed concise draft. Controller: Jennie McCrea, trading as Eden Flowers; main customer database: Hetzner in Finland. Explicit draft banner and pending recipients, transfers, retention and automated-fraud/cookie checks. Routes /en/privacy, /sv/privacy and /fi/privacy with language alternates; new strings use ~t and remain English until translation generation is requested. Footer, newsletter form and checkout link to the draft. Root layout supports page-specific robots metadata; privacy is noindex and remains absent from the sitemap.

Verification: mix format on all changed source/test files; 72 focused tests passed (privacy, terms, localized pages, sitemap, checkout); mix credo --strict reported no issues. No production deployment or database changes performed.

Follow-up requested: prune the visible draft substantially, keeping only essential privacy information and unresolved publication markers. Preserve existing routes, navigation and draft/noindex safeguards.

Pruned the policy copy from 609 to 343 template words (about 44% shorter). Replaced field-by-field lists and repeated explanations with concise purposes/legal bases, essential provider disclosures, cookie/security information and rights. Preserved controller/Finland hosting facts, non-subscriber Brevo purchase-statistic sharing, draft markers, section navigation, routes, links and noindex/sitemap safeguards. Added a rendered-notice regression check under 400 words plus essential rights assertions. Verification: 73 focused tests passed; targeted mix format and git diff --check passed. No translations generated.

Copy follow-up: add a little explanatory detail to the shortened draft without restoring the long field lists or changing unresolved legal decisions.

Slightly expanded the shortened notice from 343 to 387 template words: examples of contact/card details, the reason for delivery photos, each mapping service’s role, and identity verification for rights requests. Preserved all draft safeguards and outstanding decisions. Rendered-copy regression limit is now under 450 words. Targeted format, 73 focused tests and git diff --check passed. Translations remain ungenerated.

Retention decision: David specified that delivery photographs will be kept for two weeks. Record this in the draft while clearly marking automatic deletion as not yet implemented; do not add destructive cleanup in this copy-only change.

Recorded the approved two-week delivery-photo retention period in the draft, with an explicit automatic-deletion-not-yet-implemented marker. Other retention periods remain unresolved. Cleanup implementation is tracked by TASK-116.2 (needs-triage). Targeted format, all 9 privacy-page tests and git diff --check passed.

Policy-only follow-up approved by David in this conversation: apply the legal-review wording corrections concisely, retain draft/noindex safeguards, and track technical changes separately. No retention jobs, Brevo changes, Stripe/consent behaviour, emails, translations or production operations are authorised by this copy change.

Applied the policy-only legal-review corrections: Customer versus Recipient photo sharing, checkout-created accounts and optional fields, purpose-specific lawful bases/interests, accurate six-/ten-year accounting timing, intended versus unenforced retention, approximate routine-backup rotation, overseas/cookie/Article 14 gaps and free rights requests with timely extension notices. Removed the unsupported twelve-month enquiry-deletion promise and request-only photo-expiry workaround. Preserved draft/noindex, existing layout/links and current provider behaviour; no technical processing changes or translations generated. Technical follow-ups: TASK-116.2 (existing photos), TASK-116.3 (retention), TASK-116.4 (Brevo), TASK-116.5 (Stripe/consent), TASK-116.6 (Recipient information), all still needs-triage. Verification: 76 focused privacy/terms/localized-page/sitemap/checkout tests passed, targeted format check and git diff --check passed. Unrelated concurrent homepage/testimonial changes were left untouched.

After WIP commit 355ccc83, tightened the public copy from 704 to 568 template words (about 19% shorter). Removed repeated explanations while retaining controller/contact information, current collection/sharing, lawful bases, statutory accounting timing, unresolved retention/transfer/cookie/Recipient issues, and all rights. Tightened the rendered-copy regression limit from 800 to 650 words. Draft/noindex and existing routes/links remain unchanged. No translations or technical processing changes. Verification: all 76 focused privacy/terms/localized-page/sitemap/checkout tests passed; formatting and git diff --check passed. The copy-tightening changes remain uncommitted as requested after the WIP checkpoint.

Copy-only follow-up requested by David: remove visible draft caveats and move unresolved details to TASK-116 notes. Kept the update date, known processing facts, statutory accounting wording and current error/routine-backup periods. Removed unconfirmed overseas-safeguard copy, account-expiry work notes and the unimplemented photo-retention target rather than inventing operational guarantees. No processing, translations or SEO settings changed. Updated regression tests to reject draft/work-in-progress wording and unimplemented two-week promises.

Verification after removing public caveats: 76 focused privacy/terms/localized-page/sitemap/checkout tests passed; targeted formatting and git diff --check passed. Changes remain uncommitted.

Requested presentation/copy follow-up: restrained sans-serif page/section headings and sidebar links, normal body-text colour, and six concise storage/sharing bullets instead of ten. Smaller mapping/security/mailbox providers are disclosed by category rather than listing HERE/Mapbox/Google Maps/Cloudflare individually. Main hosting/payment/email providers, non-subscriber purchase-statistic sharing, accountant access and purchaser/Recipient photo distinction remain disclosed. No technical processing or date changes. Verification: 55 focused privacy/terms/localized-page/FAQ tests passed; targeted format check, Tailwind build and git diff --check passed.
<!-- SECTION:NOTES:END -->
