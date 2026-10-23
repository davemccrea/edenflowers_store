---
id: TASK-103
title: Split app.js into modules by concern
status: needs-triage
assignee: []
created_date: '2026-10-23 07:51'
labels:
  - developers
  - spec
dependencies: []
priority: low
type: refactor
ordinal: 212000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
app.js only sets up the LiveSocket and imports one module per behaviour.

**Why:** app.js is 543 lines of unrelated global behaviour, mostly admin: Cinder keyboard and ARIA fixes, the unsaved-changes warning, page transitions, the "/" search shortcut, the nav drawer swipe and Fastmail app links, mixed with shared drawers, copy-to-clipboard and topbar. Splitting it lets someone read or change one behaviour without paging through the rest.

**What:** one bundle still; this is file organisation only. A separate admin bundle was considered and rejected: the admin-only code is a few KB, not worth a second entry point and layout wiring. Possible modules: js/admin/cinder_a11y.js, unsaved_forms.js, transitions.js (it hands onDocumentPatch to the LiveSocket), nav_swipe.js, fastmail_links.js, search_shortcut.js, plus js/drawers.js and js/copy.js.

**Open:** the module boundaries, and how transitions.js and the Cinder fixes hand their `dom` callbacks to the LiveSocket.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 app.js holds only imports, the LiveSocket setup and its connect
- [ ] #2 Admin behaviours (unsaved warning, transitions, Cinder keyboard access, drawer swipe) work as before
<!-- AC:END -->
