---
id: TASK-141.4
title: Let Jennie write her own notice for the bar
status: done
assignee: []
created_date: '2026-10-28 20:53'
updated_date: '2026-10-29 03:00'
labels:
  - wontfix
dependencies: []
parent_task_id: TASK-141
type: feature
ordinal: 278000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie needs to announce things the system can't know, like an order deadline for Mother's Day, without asking a developer.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An admin page edits one notice with en/sv/fi text and a Show toggle
- [ ] #2 While shown, the notice replaces everything else in the bar
- [ ] #3 Blank sv/fi text falls back to English
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-29 03:00

---

Built, then dropped on 2026-10-29: Jennie would rarely use her own notice, and an on/off notice risks going stale. Full build saved as a patch outside the repo.

---
<!-- COMMENTS:END -->
