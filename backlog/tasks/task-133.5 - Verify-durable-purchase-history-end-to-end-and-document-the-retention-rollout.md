---
id: TASK-133.5
title: >-
  Verify retained purchases and manual pay-at-course bookings and document
  rollout
status: done
assignee: []
created_date: '2026-10-25 22:24'
updated_date: '2026-10-26 08:25'
labels: []
dependencies:
  - TASK-133.3
  - TASK-133.4
references:
  - CONTEXT.md
  - docs/adr/0002-payments-are-records.md
  - docs/adr/0004-orders-are-the-sales-record.md
  - docs/agents/email-map.md
  - lib/edenflowers/email/previews.ex
  - test/edenflowers/payments
  - test/edenflowers/accounting/monthly_report_test.exs
  - test/edenflowers_web/features/admin
parent_task_id: TASK-133
type: task
ordinal: 260000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The finished design must retain real money while keeping admin work simple. The previous green suite did not protect the removed deletion races, and the newly agreed manual-booking semantics deliberately reverse the earlier assumption that confirmed means paid. Integrated proof and updated language are essential to avoid implementing the obsolete Invite/Archive specification.

Each implementation step includes its tests. Close the revised parent matrix with focused resource/worker/UI/accounting assertions: unpaid manual booking counts places, paid manual entry records its actual method, later offline/link payment does not confirm twice, website checkout remains pending until payment, cancelled records still receive/settle late money and database constraints preserve ledger history. Confirm no new Archive or Invite workflow exists and cancelled orders remain available through existing Cinder All/search/direct access.

Amend CONTEXT.md, ADR-0002/0004, resource descriptions, course/customer/admin copy, email previews/templates/translations and relevant job/email documentation consistently. Record that confirmed course booking is a commitment independent of payment; manual entries default to pay at course and can bypass online cutoff/capacity; customers still do not self-edit/cancel confirmed course bookings. Replace obsolete only-Stripe/Invite/paid-only/automatic-receipt statements without reverting unrelated checkout/refund behaviour.

Verify real senders, attachment/stamp logic and drawer previews for unpaid/paid manual confirmations, ordinary online paid confirmation, later actual Payment received, reminders and cancellation. Run mix print_emails sv fi en and review every language as required; unpaid confirmation never attaches/stamps a receipt. No new payment framework or legal retention period.

Rollout must account for real pending old Invites through explicit human review rather than auto-confirming/deleting them, preserve their existing payment identities/links/intents, and neutralize obsolete queued/scheduled registration-discard jobs. Document restrictive-FK migration/rollback limits and the existing five-minute/seven-day reconciliation scope/manual recovery route. Actual deployment or direct production access remains separately approved and backup-first. No production repair, historical-record fabrication or speculative recovery is part of editing this issue.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The revised parent outcome matrix passes through actual resource/worker/UI seams, including both relevant edit/payment orderings, manual unpaid/paid/later-payment flows, cancellation and retained late money.
- [x] #2 Full tests and mix precommit pass with migration/snapshot consistency; existing customer history, checkout, payment/refund deduplication, booking counts, receipts and monthly accounting remain covered.
- [x] #3 Paid/unpaid/manual/online confirmation, later payment, reminder and cancellation scenarios are in Email.Previews; real sender/attachments/stamps/drawer previews agree, and mix print_emails sv fi en is reviewed.
- [x] #4 CONTEXT/ADR/resource/job documentation explicitly separates confirmed from paid, supersedes Invite/payment-link-only assumptions, states cancellation plus existing filtering, and adds no Archive workflow or paid flag.
- [x] #5 Legacy pending-Invite review, obsolete purge-job retirement, restrictive-FK migration/rollback, point-in-time settlement, reconciliation cutoff/manual recovery and separate privacy retention are documented; no production action or data deletion occurs.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Verify the parent matrix after TASK-133.3 and TASK-133.4 integrate with the shared late-payment/database work. Add only missing cross-boundary tests, then run mix precommit and all email rendering review. Amend domain/job docs and preserve a clear decision history of why paid-only manual booking and Archive/Invite proposals were superseded. Document human review of real legacy Invites and safe queued-purge/migration rollout without deploying.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Integrated verification complete: mix precommit passed (1,665 tests, zero failures; strict Credo, formatting and generated migration/snapshot consistency). mix gettext.extract --check-up-to-date and git diff --check passed. Reviewed mix print_emails sv fi en paid/unpaid/part-paid confirmation and reminder renders. Added actual sender versus pre-save preview tests for all three money states, actual course receipt preview, course offline-plus-Stripe double collection, and processing cancellation-response preservation in shared cancellation and checkout replacement. Closed paid-only account assumption: confirmed unpaid bookings show pay-at-course Balance, hide receipt link and refuse receipt download through resource receipt_available?; paid fixture records real money. CONTEXT and ADR-0002/0004/0005/0006 now document commitment versus payment, explicit collection, retained history, old decisions superseded and queued email/job behaviour. docs/purchase-retention-rollout.md covers legacy-Invite human gate, stopping old processes, obsolete-job cancellation migration, restrictive FKs, age-window/manual recovery limits, rollback incompatibility and separate privacy policy. Dev database seeded and server available for user testing. No production data inspection, mutation or deployment; no automated browser visual QA.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-26 04:45

---

Updated integration scope to confirmed-but-unpaid manual bookings and existing table filters. Earlier archive/Invite-withdrawal verification is obsolete and must not drive implementation.

---

author: @claude
created: 2026-10-26 04:46

---

Integration scope now follows the confirmed manual pay-at-course model and existing Cinder filters. Old acceptance of an Archive feature and retained Invite-withdrawal workflow is superseded; do not implement those from historical comments.

---

author: @claude
created: 2026-10-26 08:25

---

Follow-up from user testing: removed conditional-section blank-line leakage in course confirmation/reminder templates. Added a regression over every affected preview scenario in sv-FI, fi and en-GB; confirmed it failed before the fix and passes afterward. Reran mix print_emails sv fi en and reviewed paid/unpaid/part-paid/reminder spacing in all languages. mix precommit passes with 1,666 tests. Wording/payment behaviour unchanged; worktree and testing server retained at user request.

---
<!-- COMMENTS:END -->
