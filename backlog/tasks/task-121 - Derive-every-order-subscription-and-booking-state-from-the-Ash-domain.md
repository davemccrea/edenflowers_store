---
id: TASK-121
title: 'Derive every order, subscription and booking state from the Ash domain'
status: in-progress
assignee: []
created_date: '2026-10-25 10:08'
updated_date: '2026-10-25 13:28'
labels:
  - spec
  - developers
dependencies: []
priority: medium
type: refactor
ordinal: 240000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
No LiveView or controller works out an order's, subscription's or course booking's state itself: each reads a calculation, aggregate or relationship on the resource, and the actions validate against the same ones.

**Why:** The web layer re-derives rules the domain already has (cancellable, deletable, upcoming, overdue, the next occurrence), and some copies have drifted: the account timeline's 'upcoming' course disagrees with CourseRegistration.upcoming?. One rule in one place stops that.

Decisions (grilled 2026-10-25):
- Keep in the web layer only what is presentation: gettext labels for a status atom, checkout step routing, list splitting for display, copy that quotes constants.
- Customer order status becomes an enum calculation; account_live only maps it to a label.
- CourseRegistration.upcoming? wins over the timeline's date-only rule.
- The cancel drawer's suggested refund becomes a refund_on_cancelling calculation on both payables, and :cancel uses it when no refund is given.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 No web module compares state, status, fulfillment_status or payment_status to decide what an order, subscription or booking can do or is
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The five review findings are addressed with regression tests: receipt availability, pending course payment confirmation and upcoming?, refunded-order reminder eligibility, shared order-email eligibility, and admin subscription capabilities. Added a release migration-stage check that blocks replacing the app while legacy awaiting_payment course registrations exist, without modifying those rows. Updated the glossary, cleared existing lint blockers, and pinned the no-photo fixture to nil to prevent random test failures.

After the other agent reverted their work, verified these edits remain intact. Their payment/discard safety fixes and tests are excluded from this commit; the stale-registration deletion risk remains unresolved. Final verification of this isolated tree: mix precommit passes (1640 tests, 0 failures), including formatting, strict Credo, schema codegen and compilation checks. No production access or deployment was performed.

Parent remains in-progress: the five targeted findings are resolved, but this follow-up does not certify a fresh exhaustive pass of the broad no-web-state-comparisons criterion.
<!-- SECTION:NOTES:END -->
