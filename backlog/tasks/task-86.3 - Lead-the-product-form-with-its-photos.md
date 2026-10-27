---
id: TASK-86.3
title: Lead the product form with its photos
status: done
assignee: []
created_date: '2026-10-21 17:33'
updated_date: '2026-10-27 13:57'
labels:
  - quick
dependencies:
  - TASK-86.1
parent_task_id: TASK-86
type: feature
ordinal: 178000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Photos are what make a product and sizes pick from them, so they come first, and adding them shows what's happening.

See TASK-86 Photos.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Photos sit in the main column below name and description, above sizes
- [x] #2 Each tile has always-visible make-main and remove icon buttons with accessible labels
- [ ] #3 Files dropped anywhere on the Photos card upload, each showing its preview with a progress overlay
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @codex
created: 2026-10-21 21:10

---

Commit db603ce1 intentionally moved name and description above Photos. The gallery still precedes Sizes. Drop upload and progress are implemented, but the drop target wraps only the gallery body, not the whole Photos card, so AC #3 remains open.

---

author: @codex
created: 2026-10-21 21:10

---

Remaining work is the Photos card drop target. Upload previews and progress already work; extend the target from the gallery body to the whole card, then verify dropping on the heading/description as well as the tiles.

---

author: @claude
created: 2026-10-27 13:57

---

Launch triage 2026-10-27 with David: marked done. Dropping files on the gallery works; extending the target to the card heading isn't worth the time. AC #3 left unchecked deliberately.

---
<!-- COMMENTS:END -->
