---
id: TASK-58
title: Consolidate fulfillment confirmation email details in the order log
status: ready-for-agent
assignee: []
created_date: '2026-10-19 06:39'
labels:
  - spec
  - admin
  - quick
dependencies: []
references:
  - lib/edenflowers_web/features/admin/order_detail_live.ex
  - lib/edenflowers_web/features/admin/order_log.ex
  - test/edenflowers_web/features/admin/order_detail_live_test.exs
priority: medium
type: feature
ordinal: 124000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Show successful fulfillment confirmation email details once, in the admin order log, while keeping unsent states actionable near fulfillment.

**Why:** Jennie currently sees duplicate success information and ambiguous confirmation-email wording. One clear log entry makes it easier to check what was sent, when, and to whom.

Hide the separate confirmation-email section after a successful send. Rename the log entry to “Fulfillment confirmation emailed” and include the actual recipient address and locale-formatted send date/time. Keep compact status information near fulfillment for pending, queued, sending, automatically retrying, skipped, missing-address, and failed states, preserving existing guidance, refresh behavior, and retry actions.

Historical recipients must reflect the address used at send time, not the current customer address. If older records lack that information, omit the recipient or explicitly indicate it is unavailable. Keep initial order confirmation/receipt emails distinct. Update affected tests and translations.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Successful sends appear in the log as ‘Fulfillment confirmation emailed’, with no duplicate success section.
- [ ] #2 The log includes locale-formatted send date/time and the recipient recorded at send time; later customer email edits cannot change historical recipient information.
- [ ] #3 Older records without a recorded recipient do not present the current customer email as the historical recipient.
- [ ] #4 Unsent and failed states remain visible near fulfillment, with existing automatic refresh, error guidance, and retry actions preserved.
- [ ] #5 Affected tests and translations cover the updated wording, successful-send display, recipient history, and unsent/error behavior.
<!-- AC:END -->
