---
id: TASK-116.2
title: Delete delivery photos after two weeks with an Oban job
status: needs-triage
assignee: []
created_date: '2026-10-26 17:13'
labels: []
dependencies: []
parent_task_id: TASK-116
type: task
ordinal: 263000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** David chose a two-week retention period for delivery photos. The shop currently retains uploaded photos without expiry, so the privacy notice cannot yet promise that they are deleted after two weeks.

Add an Oban cleanup job for delivery photographs, with lifecycle rules in the Ash resource rather than the LiveView. Delete expired photo files and handle their order references so the admin and any later fulfillment-email attempts do not show broken images or fail unexpectedly. Cleanup must be safe to retry and must not affect product, course or other uploaded images, purchase records or accounting history.

**Current implementation:** Delivery photos are stored under :uploads_dir through PhotoUpload, referenced by Order.delivery_photo_slug, and served through imgproxy. The left-at-door email attaches a resized JPEG, so deleting the original does not delete email attachments. Order changes also have PaperTrail history.

**Decided:** Delivery photos should be retained for two weeks.

**Open before implementation:**
- Confirm when the 14-day period starts (recommend the time the photo is stored, recorded explicitly; do not use the mutable order.updated_at).
- Confirm how already-existing photos are dated and handled safely.
- Define the retention scope for resized/cache copies, mailbox/Brevo attachments and backups; recipient-held email copies cannot be recalled by this job.
- Decide behavior for fulfillment-email retries or resends after the photograph expires.

Until cleanup is implemented and verified, keep the privacy page marked as a draft and distinguish the agreed retention period from enforced behavior.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An Oban job removes delivery photos after the agreed two-week period and handles repeat runs and already-missing files safely.
- [ ] #2 Expired order-photo references and fulfillment-email retry/resend behavior are handled without broken image links or unexpected failures.
- [ ] #3 Tests cover retention boundaries, repeat runs, legacy photos and isolation from other uploads and purchase history.
- [ ] #4 The privacy notice accurately reflects the implemented retention scope, including any separately retained copies.
<!-- AC:END -->
