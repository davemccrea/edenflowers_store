---
id: TASK-103
title: Split app.js into modules by concern
status: ready-for-human
assignee: []
created_date: '2026-10-23 07:51'
updated_date: '2026-10-23 09:16'
labels:
  - developers
  - spec
  - quick
dependencies: []
priority: low
type: refactor
ordinal: 212000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
app.js only sets up the LiveSocket. Global behaviour lives beside the markup it serves, or in a small module when it configures the socket.

**Why:** app.js is 541 lines of unrelated global behaviour, mostly admin, so reading or changing one behaviour means paging through all of it. Following TASK-102, code sits with what it belongs to.

**Decisions** (grilled 2026-10-23):
- Listeners owned by one component become `Phoenix.LiveView.ColocatedJS` (side-effect only, no `name`) beside it, as the ColocatedJS docs describe for global event listeners:
  - drawer open/close, Escape, backdrop tap, swipe-to-close and the admin nav drawer swipe-open: beside `drawer/1` in core_components.ex. The swipe-open writes the drawer's inline translate and copies swipe-to-close's release rule, so the gesture code stays in one place; `navDrawer()` keeps the admin id and breakpoint.
  - "/" search shortcut: beside the search input in Layouts.admin.
  - copy and Fastmail app links: beside their components in admin/components/components.ex.
  - expand/collapse all: emails_live.ex.
- Socket wiring becomes flat modules under assets/js/: admin_transitions.js (onDocumentPatch), cinder_a11y.js (dom callbacks and observer), customer_select.js (LiveSelect override; live_select writes phx-hook="LiveSelect" itself), unsaved_forms.js (six forms share it and it reads liveSocket).
- app.js keeps imports, topbar, phx:js-exec and the LiveSocket setup.
- Only moves: no behaviour changes. A separate admin bundle was rejected: a few KB, not worth a second entry point.
- One commit, landed with TASK-102 by `wt merge --no-squash`.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 app.js holds only imports, topbar, phx:js-exec and the LiveSocket setup and connect
- [x] #2 mix test, mix format --check-formatted and credo pass
- [ ] #3 Drawers (open, Escape, backdrop, swipe), nav drawer swipe, "/" search, copy, Fastmail links, expand/collapse all, unsaved warning, admin transitions and Cinder keyboard access work in the browser with a clean console
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
app.js is 57 lines. Socket modules: customer_select.js, cinder_a11y.js (exports cinderDom), admin_transitions.js (exports onDocumentPatch), unsaved_forms.js (reads window.liveSocket at beforeunload). ColocatedJS beside: drawer/1 (all drawer code incl. nav swipe-open), Layouts admin_search ("/"), Admin.Components copy_button and email_link (script first: HEEx leaves no whitespace before an inline element), EmailsLive (expand/collapse). Comments that pointed at app.js now name the new homes.

Headless Chrome on dev: cart drawer opens on add (js-exec), Escape, phx-show, backdrop tap and touch swipe close it; touch swipe opens the admin nav drawer; Fastmail link taken over on a phone; unsaved warning confirms before leaving; customer combobox ARIA; "/" focuses the search; Cinder sort header is a keyboard button and Enter sorts; expand/collapse all; admin navigation. No console errors. View transitions only animate in the installed app (display-mode: standalone), which headless Chrome cannot emulate, so those were not watched animating.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-23 09:16

---

Left for a human: admin page transitions only animate in the installed app, which headless Chrome cannot emulate. Open the installed admin on a phone, move between pages (push, pop, fade), then check AC #3 and set done.

---
<!-- COMMENTS:END -->
