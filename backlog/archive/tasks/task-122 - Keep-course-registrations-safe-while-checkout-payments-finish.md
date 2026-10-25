---
id: TASK-122
title: Keep course registrations safe while checkout payments finish
status: done
assignee: []
created_date: '2026-10-25 13:34'
updated_date: '2026-10-25 14:44'
labels:
  - customers
  - admin
  - wontfix
dependencies: []
priority: high
type: bug
ordinal: 244000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Abandoning course checkout never deletes a registration needed by an in-flight payment, and callers show the current outcome.

**Why:** Stripe can finish a payment while the customer changes their booking or a cleanup job deletes checkout data. Losing its registration or offering a second checkout risks taking money without the expected booking.

Agreed scope: one ID-based Ash operation returns no registration when deleted/already absent, the current registration on expected retention, and an error on unexpected failure. Reload and cancel the current intent before deleting, accept its cancellation webhook clearing it, and reject a different intent. Keep pending status and custom-order deletable? conditions on the database delete. Preserve the existing booking-confirmation work; no retry loops, persisted states or payment framework.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The domain safely handles stale callers, webhook-cleared or replaced intents, processing/succeeded payments and already-absent registrations without hiding unexpected errors
- [x] #2 Change booking and failed-payment returns handle retention without resetting checkout or crashing; invite withdrawal uses the same operation
- [x] #3 Custom-order deletion retains an order paid while its old intent is being cancelled
- [x] #4 Regression tests exercise real completion/cancellation handlers, authorization and the guarded abandoned-registration purge; precommit passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Implemented the agreed ID-based discard_registration operation as an Ash action. It returns nil for deleted/absent records, reloads on explicitly recognized PaymentInProgress, StaleRecord or same-resource NotFound errors, and preserves unexpected failures. The shared pre-delete cancellation change reloads the current intent, cancels it before deletion, and filters the delete to the checked intent or nil (a cancellation webhook may clear it). A newly attached intent stops deletion. Custom-order deletion also filters on deletable? so a replacement payment completed while Stripe cancels the old intent prevents deletion.

Updated Change booking, failed-return handling and invite withdrawal; retained pending-confirmation display/paid notifications. Added the processing-payment message in sv/fi/en. Twenty new tests cover domain races, real payment/cancellation handlers called from Stripe mocks, expected retention vs unexpected failures, authorization, already-absent records, background cleanup and web callers. Existing custom-order admin feedback now recognizes the typed payment-in-progress error.

Verification: initial domain regressions reproduced stale-copy and replacement-intent deletion. Final mix precommit passes: 1660 tests, 0 failures; compile, strict Credo, formatting and schema checks pass. git diff --check passes. No live Stripe timing or production access was performed.

Saved as WIP at the user's request. Local checks pass, but this is a checkpoint rather than a final sign-off; live Stripe timing remains unverified.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-25 14:44

---

Superseded by TASK-123: checkout now revises the registration in place, so customers no longer delete records Stripe may be paying. Reverted the discard_or_retain action and the extra CancelOpenPaymentIntent/delete_custom guards; kept the typed PaymentInProgress error.

---
<!-- COMMENTS:END -->
