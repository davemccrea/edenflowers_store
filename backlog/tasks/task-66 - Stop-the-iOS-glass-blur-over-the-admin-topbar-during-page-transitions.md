---
id: TASK-66
title: Stop the iOS glass blur over the admin topbar during page transitions
status: ready-for-human
assignee: []
created_date: '2026-10-20 06:18'
labels:
  - spec
  - admin
dependencies: []
priority: low
type: research
ordinal: 140000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
In the installed admin app on iOS, the topbar and search bar blur slightly while a page transition runs, and turn sharp again once it ends.

**Why:** A small visual glitch on every page change in the app Jennie uses all day. Not worth a workaround, but worth fixing if Safari makes it easy.

iOS standalone draws a glass blur over the top edge unless a sticky or fixed element covers it (see 4a1e5f85). During a document view transition the page is replaced by snapshots, so iOS no longer finds the sticky topbar and blurs it.

Tried and reverted on 2026-10-20 (56af6ff1, 47a7dc90, 4e815057, reverted in 4688be87..01c1fda0):
- Element-scoped view transitions (`#admin-page.startViewTransition`) with the topbar moved out of the LiveView into the root layout. Works in Chromium, but Safari does not support scoped transitions, so iOS got no transitions at all.
- A document transition capturing only `#admin-page`, with the topbar live underneath. Needed pinning and clipping hacks to handle scrolled pages; judged too hacky for the gain.

What to check: whether Safari now supports element-scoped view transitions (`Element.prototype.startViewTransition`), or no longer blurs the top edge while a view transition runs. If either holds, the fix is small.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Checked whether the current iOS Safari supports element-scoped view transitions or stops blurring the top edge during view transitions
- [ ] #2 If it does, the admin topbar stays sharp through page transitions in the installed app
<!-- AC:END -->
