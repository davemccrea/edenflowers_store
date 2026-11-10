---
id: TASK-185
title: Warn admin editors about external saves without protecting drafts
status: done
assignee:
  - '@openai'
created_date: '2026-11-09 18:12'
updated_date: '2026-11-09 22:00'
labels:
  - developers
  - admin
dependencies: []
references:
  - 9025f388
  - TASK-184
priority: low
type: refactor
ordinal: 350000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Admin editors alert the shop when saved data changes elsewhere, without preventing the user from saving.

**Why:** This small shop rarely has concurrent editors. Per-form dirty tracking and unfinished-edit protection cost more maintenance than they justify; a clear warning and PaperTrail history are sufficient.

Confirmed with David: cover all admin editors including inline forms/drawers, not just commit 9025f388. Warn regardless of dirty state; Save stays available and may overwrite newer changes. Offer discard/reload. Ignore own writes. Lists continue automatic refresh. No merging, recovery machinery or database concurrency locking. Supersedes TASK-184's draft-preservation policy.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 All admin editors with existing saved data or changing saved dependencies visibly warn on external changes while leaving write actions available.
- [x] #2 Explicit reload loads current data and discards unfinished edits; own saves do not produce external-change warnings.
- [x] #3 Dirty-form tracking and conditional draft-preservation paths are removed; list refresh/coalescing remains intact.
- [x] #4 Behavior tests cover clean and edited forms, reload, own writes and saving after warning; refresh documentation and gettext catalogues are updated.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Admin detail/editor notifications only warn: retain the complete saved snapshot, forms, drawer state and errors; ignore own notifications. Remove saved-data refresh paths, detail timers and missing-form repair machinery. This supersedes the earlier partial-refresh approach.
2. Explicit Reload navigates/remounts to replace the whole page. Successful local actions explicitly reload saved data/forms together, including committed payments with failed receipt emails. Failed actions retain drafts and warning state.
3. Apply to order/course/subscription/customer detail pages and calendar editing. Keep list/dashboard and customer-facing live updates. Hybrid pages may refresh list-only tables independently. Subscribe subscription editors to product and fulfillment-option dependency changes for warnings.
4. Update the refresh review rules and behavior tests: no notification database reads or saved-state mutations; unchanged controls/prices/history until reload; successful local updates and refused-action draft preservation. Preserve pre-existing storefront fixes and unrelated user work.
5. Extract and verify reference-only catalogue updates; run focused tests, full precommit and gettext freshness/check/stats. No deployment, production writes or commit requested.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Removed all admin dirty/dirty_forms/set_data preservation logic. Added assertive overwrite warning and shared drawer presentation, kept all saves available. First focused run exposed expected policy changes in old tests; updated them and added cross-editor action-driven coverage. Tidewave is running, but browser_eval reports no connected browser, so visual browser verification is currently unavailable.

Focused run passed 418 tests; first full just test passed JavaScript plus 2185 Elixir tests (0 failures, 1 skipped). Strict Credo found two new alias-order issues, corrected. Ash codegen check passed. Added existing info-flash notification alongside persistent page/drawer warnings so an external save is noticed even when the page banner is off-screen; this remains informational and never prevents saving. Re-running verification after that final alert enhancement.

Final verification: just test passed JavaScript plus 2185 Elixir tests, 0 failures, 1 skipped (seed 709309). Final focused run after the voucher-cancel refinement passed 67 tests (order detail, editor action matrix and shared PubSub behavior). Strict Credo, changed-file format check, warnings-as-errors compilation, Ash codegen check, gettext.check, gettext.stats, extract-up-to-date and git diff --check passed. Impeccable detector returned no findings. Catalogue semantic diff is exactly one English warning replacement in admin.pot/en/sv/fi, with existing translations untouched; the warning uses English fallback in sv/fi as before.
AC evidence: EditorNoticeTest exercises real Ash updates and reloads for course edit/detail/booking creation, promotion, order edit, fulfillment pricing/calendar, order creation dependencies and account; course, welcome-offer and note tests save successfully after external-save warnings. Product tests cover clean and edited forms, stock changes, flash notification and reload. Order/subscription/invoice tests assert warnings inside drawers; unit helper tests prove own writes never add warnings or suppress an existing warning. Existing list/coalescing and full-suite tests remain green. No connected Tidewave browser, so rendered browser appearance was not visually verified. No commit, deployment or production writes.

Added Swedish/Finnish warning, reload label and confirmation translations; David requested active translations without fuzzy flags. Review evidence records exact wording in priv/gettext/review-queue.md and catalogue comments, with native review/Jennie's approval still outstanding.

Translation follow-up verified: gettext.check passed; gettext.stats shows 812/932 admin entries ready in each of sv/fi (three newly active entries per language), no fuzzy entries; extract --check-up-to-date and git diff --check passed. Focused translation/product/PubSub run passed 41 tests. Catalogue comments and the review queue record exact AI-reviewed wording without asserting native/Jennie approval. User requested committing the complete session change.

Deployment review reproduced two crashes with sandboxed LiveView tests: opening Refund after another process fully pays an order passes a nil form to Drawers.refund_form; removing the final product variant broadcasts a change and renders selected_variant=nil. Existing full precommit passed 2191 tests, revealing missing transition coverage.

Deployment follow-up implementation: order refreshes now initialize only missing eligible payment/refund forms, while own saves explicitly rebuild them; existing note/payment drafts remain untouched on external notifications. Product pages navigate to the localized store when no sizes remain (including initial visits), and select a surviving size/photo otherwise. Course/customer/subscription detail collection topics now share the existing refresh timer; record topics remain immediate. Successful course payment/cancel/seat/email operations refresh saved data and clear stale warnings; failed submissions retain them. Permanent regression coverage reproduced both crashes and both course warning failures before fixes. Focused run: 151 tests passed (seed 338676). Production compile --warnings-as-errors passed; 36 local public pages across en/sv/fi returned HTTP 200. Full precommit is running; no browser payment/3DS/wallet verification, deployment or production writes.

Full precommit follow-up: all static, translation and JavaScript checks passed; 2198 Elixir tests exposed one additional customer-detail subscription test assuming synchronous collection refresh (seed 27393). Updated customer-detail notification assertions to wait for the scheduled refresh, including negative scope assertions so they exercise the refreshed state. No production-code change was needed. Re-running the complete gate.

Final deployment follow-up verification: mix precommit passed all checks, JavaScript and 2198 Elixir tests with 0 failures and 1 skipped (seed 127489). The previous seed 511055 warning failure was test interference from parallel tests publishing to the intentionally global booking collection; the two absence-of-warning regressions now live in the existing async:false EditorNoticeTest rather than weakening notification behavior. Production compilation passed, 36 local public-page checks passed, and no database migrations, dependencies, user-facing strings or storefront topic contracts changed. Temporary reproduction file removed. No commit, deployment or production writes; browser checkout, 3DS and wallets remain unverified.

Confirmed in conversation: external refreshes are unnecessary in admin editors and create mixed saved-record/form snapshots. User explicitly requested fully removing that model after reviewing the proposed warning-only policy.

Removed all notification-driven data reloads and timers from order/course/customer/subscription detail pages; external messages now only mark stale, own messages leave the page unchanged. Folded order saved-data/form assignment back into one function and removed missing-form repair logic. Local committed actions explicitly reload, including a recorded payment whose receipt failed; refused actions retain drafts and warning state. Calendar editor notifications no longer replace the calendar; standalone/list-only tables still refresh automatically. Added subscription product/fulfillment dependency warnings, customer-detail reload notice, local appearance warning clearing, and regression tests for unchanged detail assigns/no database reads, payment transitions only after reload, readiness refusal drafts, and subscription-price choices. Updated refresh policy. Focused run: 192 tests, one obsolete last-customer-order reload expectation corrected to the existing Customer not found redirect. Full precommit underway. Catalogue update has zero message/translation changes; verified all catalogue diffs are source-reference-only.

Full precommit: static/gettext/codegen/Credo/JavaScript passed; 2201 Elixir tests had one warning-absence assertion interrupted by another async test's global order publication (seed 448404). Order detail tests now run async:false because their absence-of-warning assertions require global-topic isolation, matching existing editor tests. Re-running the same seed. Preserved order-specific background email-failure flash warnings, scoped to the displayed order's record topic so unrelated collection failures only produce the generic stale notice.

Final verification for complete warning-only notification policy: mix precommit --seed 448404 passed all static/codegen/translation/JavaScript checks and 2201 Elixir tests (0 failures, 1 skipped). After the final record-topic scoping of email-failure flashes, 72 focused detail/order/editor tests passed with the same seed; final warnings-as-errors compile, format, strict Credo, gettext.check/stats and extraction freshness all passed. git diff --check passed. All seven changed catalogues were verified source-reference-only, with no source or translation wording changes. DetailRefreshTest verifies collection and record messages perform zero database reads, do not mutate saved assigns/forms, schedule no refresh, and ignore own notifications. LiveView tests cover explicit reload, consistent payment/refund controls, related-history snapshots, dependency-price warnings, local action reloads and refused-action draft preservation. Existing list/dashboard/storefront tests pass in the full suite. Browser checkout/3DS/wallets not exercised; no production writes, deployment or commit.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Replaced admin dirty-form tracking and form rebasing with a warning-only policy across all custom editors. External saves send a flash notification and show a persistent assertive page/drawer notice with confirmed discard/reload; saving stays available. Added missing record/dependency subscriptions, kept automatic list refresh/coalescing and own-write behavior. Swedish/Finnish translations for the warning, reload button and discard confirmation are active (no fuzzy flags), as David requested; native/editorial review remains recorded as pending. Verification: JavaScript plus 2185 Elixir tests passed (1 skipped), final 67 focused behavior tests and 41 translation/product/PubSub tests passed; format/Credo/compile/codegen/gettext checks passed. Browser appearance was not visually checked because no browser was connected. No deployment or production writes.

Deployment-review fixes: prevent nil settlement-form crashes after external order payments/undo while preserving existing drafts; navigate products with no sizes to the localized store and keep surviving sizes buyable; coalesce course/customer/subscription collection refreshes with the existing timer; clear course stale warnings after committed saves while retaining them on failure. Added seven regression tests and adjusted scheduled-refresh test waits/isolation. Final mix precommit: 2198 tests, 0 failures, 1 skipped, plus JavaScript/static/gettext/codegen checks; production compile and 36 public-page checks passed. No deployment or production writes; real-browser payments/3DS/wallets unverified.

Superseding the earlier partial-refresh implementation: admin detail/editor notifications now only warn; they never refresh saved records, totals, histories, tables or forms. Removed detail timers and order missing-form repair logic. Successful local actions explicitly reload their saved data/forms, including committed payments whose receipt failed; refused actions preserve drafts and warnings. Explicit Reload remounts the whole page. Lists/dashboard and customer-facing updates remain automatic; list-only tables on hybrid pages retain independent refreshes. Added customer-detail notices and subscription pricing-dependency warnings, updated policy/tests, and retained unrelated pre-existing storefront fixes. Verification: full precommit passed 2201 Elixir tests (0 failures, 1 skipped), JavaScript/static/codegen/gettext checks; final 72 focused tests and final static/extraction checks also passed. Catalogue changes are references only. No browser payment smoke, production writes, deployment or commit.
<!-- SECTION:FINAL_SUMMARY:END -->
