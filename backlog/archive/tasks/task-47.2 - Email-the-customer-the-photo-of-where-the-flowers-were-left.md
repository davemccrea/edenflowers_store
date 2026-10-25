---
id: TASK-47.2
title: Email the customer the photo of where the flowers were left
status: done
assignee: []
created_date: '2026-10-18 18:22'
updated_date: '2026-10-18 19:10'
labels: []
dependencies:
  - TASK-47.1
parent_task_id: TASK-47
type: feature
ordinal: 110000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** A customer who wasn't home needs to know where to find their flowers.

When Jennie confirms a delivery with a photo, an "Email the photo to the customer" checkbox shows, ticked. Ticked, the customer gets a "You weren't home, so I left your flowers here" email with the photo instead of the usual delivered email.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 A delivery confirmed with a photo and the box ticked sends the photo email and not the delivered email
- [x] #2 Unticked, the usual delivered email goes out
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The emailed photo is fetched from imgproxy at 1600 px, JPEG quality 80, so a 10 MB phone photo goes out at a few hundred KB.
<!-- SECTION:NOTES:END -->
