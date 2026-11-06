---
id: TASK-180
title: >-
  Back the admin action drawers with AshPhoenix forms, so a refused action marks
  the field it refused
status: needs-triage
assignee: []
created_date: '2026-11-06 17:10'
labels:
  - spec
  - admin
dependencies: []
priority: medium
type: refactor
ordinal: 345000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The admin drawers that run an action show its errors on the fields that caused them, the way the order, product and invoice forms already do.

**Why:** Jennie sees one flash or line when cancelling, recording a payment, refunding, marking fulfilled, saving a florist note or issuing a credit note fails, often only the first error or a generic "Check the entered values", and can't tell which field to fix. The pages also copy every param into the action's inputs by hand, which drifts as actions change.

The drawers build plain `to_form(map)` forms: `PaymentActions.cancel_form/1`, `cancel/3`, `record_payment/3`, `refund/3`; the fulfillment and note forms in `OrderDetailLive`; the credit form in `InvoiceLive`; the cancel forms in `SubscriptionDetailLive` and `CourseDetailLive`. `PaymentActions.payment_error/1` keeps only the first message and `InvoiceLive.finish/3` drops the error.

Open: how `Drawers.email_edits/1` (the rewritten subject and body every drawer shares) maps onto action arguments, and whether UI-only fields like the fulfillment's "Was the customer home?" stay as params outside the action (`transform_params`) or become arguments.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Each listed drawer builds its form with AshPhoenix.Form.for_update or for_create on its action
- [ ] #2 An action's validation error shows on the field it names, not only in a flash
- [ ] #3 PaymentActions no longer maps params to action inputs by hand, and payment_error/1 is gone
<!-- AC:END -->
