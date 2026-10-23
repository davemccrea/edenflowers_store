---
id: TASK-105.7
title: Split Left at the door from Delivered
status: ready-for-agent
assignee: []
created_date: '2026-10-23 18:42'
labels: []
dependencies:
  - TASK-105.2
parent_task_id: TASK-105
type: feature
ordinal: 220000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** "Nobody was home" sends the customer to go and look, so it needs its own subject and its own words.

Delivered: subject "Your order for <recipient> has been delivered" for gifts, "Your Eden Flowers order has been delivered" otherwise. Left at the door: subject "... was left at the door", "Nobody was home when I delivered your order for <recipient>, so I left it in a safe place. The attached photo shows where.", and for gifts "You might like to let <recipient> know it's waiting." The photo is required. Tick box defaults unchanged: ticked for gifts and when nobody was home, unticked otherwise, never for pickups.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Marking a delivery with nobody home sends Left at the door with the photo
- [ ] #2 Other deliveries send Delivered
- [ ] #3 Previews on the admin Emails page cover every version, and the new copy is translated in en, fi and sv
<!-- AC:END -->
