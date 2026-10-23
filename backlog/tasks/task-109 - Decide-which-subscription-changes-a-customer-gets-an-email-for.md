---
id: TASK-109
title: 'Confirm a subscriber''s own cancellation, and tell the shop'
status: ready-for-agent
assignee: []
created_date: '2026-10-23 18:42'
updated_date: '2026-10-23 18:52'
labels:
  - spec
  - customers
dependencies: []
priority: low
type: feature
ordinal: 231000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
When a customer cancels their subscription from their account, they get a written confirmation and Jennie gets a shop notice.

**Why:** Cancelling stops a recurring charge, which the customer wants in writing, and Jennie loses a regular customer she may want to ask about.

Decided in the email grilling session on 2026-10-23. Pause, resume and change send no email.

Customer email: matter-of-fact, signed Eden Flowers, copied to info+copy@ as usual:

```
Subject: Your Florist's choice subscription is cancelled

Your Florist's choice subscription is cancelled. Your card won't be charged again.

Your delivery on Saturday 28.11.2026 has already been charged and will still come.   (only if one exists)

Questions? Reply to this email.

Eden Flowers
```

Shop notice: a ShopNotice like a new order, in Swedish, to the shop notice address, with a link to the subscription in the admin.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 A customer cancelling their subscription gets the confirmation
- [ ] #2 It names an already-charged delivery that still comes
- [ ] #3 The shop notice address gets a notice linking to the subscription
- [ ] #4 Pause, resume and change send nothing
- [ ] #5 Previews on the admin Emails page cover it, and the copy is translated in en, fi and sv
<!-- AC:END -->
