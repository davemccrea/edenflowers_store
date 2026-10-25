---
id: TASK-86.1
title: Prototype the streamlined product form
status: done
assignee: []
created_date: '2026-10-21 17:33'
updated_date: '2026-10-21 17:50'
labels: []
dependencies: []
parent_task_id: TASK-86
type: prototype
ordinal: 176000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The form feels underbaked in ways easier to judge on screen than in prose, so the layout is checked before any LiveView work.

A throwaway static mock of every decision in TASK-86 with Bouquet 1's data, at desktop and phone widths. Not kept in the codebase.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 David has reviewed the mock and any changes are written back into TASK-86
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Prototype on branch prototype/product-form (commit e306dbeb): lib/edenflowers_web/features/admin/product_form_prototype.ex at /admin/products/:id?variant=A|B|C. A = as grilled, B = photo-led split, C = sizes first with the rest folded.

Verdict (2026-10-21): A, layout unchanged. Build it with the app's components first (.input, .button, .icon_button, .badge, admin_drawer, form_section), then DaisyUI classes, and custom markup only where neither fits. Seen in the prototype: the phone header is cramped (title truncates, Save wraps).
<!-- SECTION:NOTES:END -->
