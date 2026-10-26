---
id: TASK-116.1
title: Add the approved privacy-policy draft page
status: done
assignee: []
created_date: '2026-10-26 16:39'
updated_date: '2026-10-26 17:13'
labels: []
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
<!-- SECTION:NOTES:END -->
