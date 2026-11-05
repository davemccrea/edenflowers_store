---
id: TASK-165.2
title: Start a pass-it-on code's 30 days at its first scan
status: done
assignee: []
created_date: '2026-11-05 09:15'
updated_date: '2026-11-05 16:35'
labels: []
dependencies: []
parent_task_id: TASK-165
type: feature
ordinal: 338000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** A soft deadline gets recipients to act while the flowers are fresh, and no handed-out card stays a live discount indefinitely. Counting from the first scan works for every card, linked or not, with no step from Jennie.

Decisions (grilled 2026-11-05):
- A card's Promotion has no expiration date until a customer first opens its 'Pass it on' page or first applies its code, whichever comes first. Then it expires 30 days later. Admin visits don't count.
- The page shows the date the code is valid until.
- After that the code fails with the usual expired-code feedback, and the page still shows the product without a discount (as for a used code).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A card code's first customer scan or apply sets its expiry 30 days later; admin visits don't
- [x] #2 The page shows the valid-until date, and an expired code gets no discount
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Promotion.start_validity sets a pass_it_on code's expiration_date to today + 30 when unset; skipped for admin actors. Called from ApplyPromotion (any apply: link, typed code) and PassItOnLive mount. Not recorded in paper trail.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-05 10:47

---

2026-11-05: Find card codes by Promotion kind pass_it_on (added in TASK-165), not by their batch name.

---
<!-- COMMENTS:END -->
