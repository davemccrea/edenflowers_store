---
id: TASK-184
title: Make admin refresh behavior predictable without losing unfinished edits
status: done
assignee:
  - '@openai'
created_date: '2026-11-09 16:25'
updated_date: '2026-11-09 16:45'
labels:
  - developers
  - admin
dependencies: []
priority: medium
type: refactor
ordinal: 349000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Admin pages remain current without maintainers having to track action-specific display dependencies.

**Why:** Only 1–2 people use the admin concurrently. David prioritises maintainability and reasoning over avoiding extra database reads. The recent PubSub changes introduced selective refresh paths and relation-specific publishing rules; simplify these while retaining automatic updates from customers, Stripe and background jobs.

Confirmed scope: broad collection invalidation for related data; retain record topics for editors and storefront notification behavior. Preserve unsaved forms with explicit stale/reload behavior, including voucher and subscription drawer gaps. No automatic merging, new concurrency locking, or generic editor framework.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Dashboard business-data changes refresh all dashboard data without action-name dependency maps, including calendar/bank changes and date rollover.
- [x] #2 Admin parent/detail pages refresh related saved data through broad collection subscriptions without admin relation topics or payload-based relevance checks.
- [x] #3 Unfinished input and failed-submission errors survive notifications, including voucher date and subscription drawers; relevant changes offer explicit discard/reload.
- [x] #4 Bursty list notifications remain coalesced with bounded refresh latency; existing storefront notifications remain intact.
- [x] #5 Behavior-focused regression tests pass and documented refresh rules describe the simplified approach.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Replace dashboard action/topic-specific data refreshes with one coalesced full reload (orders, attention, sales, calendar, bank); preserve presence/report message handling.
2. Remove admin relation topics and their publications. Customer/course/subscription details subscribe to related collections and reload saved data together. Remove customer-list action exceptions and order pass-it-on payload relevance traversal. Keep record-specific editor subscriptions and shared storefront topics.
3. Keep list burst coalescing but schedule only if no timer remains active; do not restart an active timer.
4. Preserve voucher-date input/errors with the existing dirty_forms mechanism. Subscription drawers keep their form while saved data refreshes, mark relevant external record/calendar changes stale, and clear stale state on close/save/reload.
5. Replace query-count/zero-read assertions that encode removed optimizations with observable refresh, ownership/filter preservation, rollover, and draft/error behavior. Remove now-unused relevance helpers and their tests. Update docs/agents/ash-liveview-review.md.
6. Run focused admin/domain tests, then the full test/check gates as practical, formatting and gettext extraction/check/stats if catalogue references change. No source-copy or translation wording changes intended.

Full suite exposed one remaining literal relation-topic test and a BalancePanelTest timeout (passes alone). Coalesce order-detail collection notifications as well as lists/dashboard so broad invalidation does not queue a heavy reload per unrelated order write; retain immediate own-record updates for editor state and email errors. This uses the same timer helper, without payload relevance filtering. Update chain notification tests to wait for that deferred collection refresh.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented broad parent/detail collection subscriptions, removed relation topics/publications and pass-it-on relevance traversal, unified dashboard business-data refreshes (including calendar, bank and report month), removed customer-list action exclusions, and changed burst timers to keep their first deadline. Voucher-date edits/errors now participate in dirty_forms; subscription drawers preserve input and show the shared stale notice inside the active drawer. No storefront notification paths or translation wording changed. Replaced optimization-specific query assertions with behavior tests. Focused admin/domain run: 418 tests, 0 failures; full suite underway. Strict Credo and gettext.check passed; extraction reports 0 new/removed/reworded messages, reference-only catalogue updates.

First full gate: JavaScript passed; Elixir 2182 tests, 2 failures, 1 skipped. One obsolete CustomOrderTest expects removed admin:orders:customer topic. One balance-panel test timed out under full-suite concurrency; isolated run passed in 1.1s. Addressing broad collection burst handling rather than increasing the test timeout.

Final verification: just test --seed 568224 passed 2181 tests, 0 failures, 1 skipped (94.7s), reusing the first full run's seed. JavaScript tests passed in the initial just test gate; no JavaScript changes. Final focused run after collection burst handling: 166 tests, 0 failures. mix compile --warnings-as-errors, mix ash.codegen --check, mix credo --strict, changed-file mix format --check-formatted, git diff --check, mix gettext.extract --check-up-to-date and mix gettext.check passed. mix gettext.stats reviewed; catalogue diff verified to contain source-reference lines only.
AC evidence: OverviewLive tests cover all business notification categories, day rollover, bank/calendar/report refresh and payment totals; customer tests retain filtering and both owners catch up when an order moves; course/subscription tests retain record scoping after broad notifications. LiveView tests preserve note/settlement/voucher drafts and voucher refusal errors, subscription change refusal errors and cancellation email drafts, with explicit reload and close/save clearing stale state. PubSubTest covers shared burst deadline, subsequent refreshes and independent keys. Full suite covers unchanged storefront paths. No browser smoke performed; interaction verification uses LiveView tests.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Simplified admin invalidation for maintainability: one dashboard saved-data reload path; broad collection subscriptions for related records; removed admin relation topics, action-name refresh exceptions and pass-it-on payload relevance traversal. Retained record topics for editors and storefront notifications, and coalesced broad order/list/dashboard bursts without restarting active timers. Fixed voucher-date draft/error protection and subscription drawer stale/reload behavior. Updated refresh standards and behavior-focused tests. Verification: 2181 Elixir tests passed, 1 skipped; JavaScript, formatting, strict Credo, warnings-as-errors compilation, Ash codegen and gettext checks passed. No translation wording changes or deployment.
<!-- SECTION:FINAL_SUMMARY:END -->
