---
id: TASK-133.1
title: >-
  Prevent Payment ledger rows from cascading away with their order or
  registration
status: ready-for-agent
assignee: []
created_date: '2026-10-25 22:24'
updated_date: '2026-10-25 22:24'
labels:
  - quick
dependencies: []
references:
  - lib/edenflowers/payments/payment.ex
  - lib/edenflowers/courses/course_registration.ex
  - priv/repo/migrations
  - test/edenflowers/payments/payable_test.exs
parent_task_id: TASK-133
type: bug
ordinal: 256000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** TASK-133 cannot preserve financial history while deleting a parent can also delete its Payments. This is the small database backstop for money already recorded; retained application records separately protect in-flight payments.

Change the Payment resource's order and course_registration foreign keys from cascading deletion to restrictive/no-action deletion. Generate the migration and Ash snapshots from the resource definitions. Preserve the two real foreign keys, exactly-one-parent check, Stripe-ID uniqueness and reversal semantics. Keep the existing course-to-registration restriction. Do not add triggers, a polymorphic parent table, unrelated schema cleanup or a production data repair.

Add tests using actual database deletes (not only Ash validations or authorization) proving that an order or registration with a Payment cannot be deleted and that its money remains. Include refunded/reversed history, since money once recorded still needs an audit trail. Verify a course with a retained registration is also protected, while an unused course can still be deleted. No deployment or production write is authorized by this task.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Payment order/course_registration foreign keys reject parent deletion; neither money rows nor parent records disappear on a rejected delete.
- [ ] #2 Generated migration and resource snapshots match the Ash definitions; existing exactly-one-parent, unique Stripe IDs and reversal behaviour remain intact.
- [ ] #3 Database-level tests cover both parent types and refunded/reversed history; the existing course-parent restriction is verified, including deletion of a course with no registrations.
- [ ] #4 The full relevant payment/refund/accounting tests and migration checks pass; no existing data is deleted or marked archived.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Change only the two Payment parent reference deletion behaviours; generate migration/snapshots; add database delete-protection assertions for both parents and course ownership; run payment/refund/accounting tests and migration consistency checks. Keep this safety change independent of UI archival.
<!-- SECTION:PLAN:END -->
