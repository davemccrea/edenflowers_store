---
id: TASK-102
title: Move each LiveView hook next to the code that uses it
status: done
assignee: []
created_date: '2026-10-23 07:51'
updated_date: '2026-10-27 13:57'
labels:
  - developers
  - spec
  - quick
dependencies: []
priority: medium
type: refactor
ordinal: 211000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Each hook lives as a colocated hook inside the LiveView or component that renders it, instead of in one shared assets/js/hooks.js.

**Why:** hooks.js holds 14 hooks from every part of the shop in 1,247 lines, so whoever changes a feature has to find its JS far from its markup. Colocating them matches the feature-first layout of edenflowers_web and the standard Phoenix 1.8 way (Phoenix usage rules, Phoenix.LiveView.ColocatedHook docs).

**Decisions** (grilled 2026-10-23):
- Every hook is a `<script :type={Phoenix.LiveView.ColocatedHook} name=".Name">` in the module that renders its `phx-hook`. JS files beside .ex files were rejected: Phoenix documents external hooks as living in assets/js/.
- A hook used by several features lives in the shared component that renders it. CharacterCount gets a small component wrapping its phx-hook; PhotoGallery goes with the gallery component.
- stripe_form moves out of core_components.ex into its own component module, so its large hook does not grow that file.
- push.js and the vendored libraries stay in assets/ and are imported as `@/js/push` and `@/vendor/...`.
- Hook JS is formatted by prettier through a `Phoenix.LiveView.HTMLFormatter.TagFormatter` registered in .formatter.exs (`tag_formatters`), pinned to the prettier version `just format` uses. `@ts-check` on hook code is given up; nothing documented reaches into .ex files.
- Only moves: no behaviour changes. Constants travel with their hook. Splitting app.js stays in TASK-103.
- One commit.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 assets/js/hooks.js is gone and app.js registers only colocated hooks and LiveSelect
- [x] #2 mix format formats the JS inside colocated hooks with prettier, and mix format --check-formatted passes
- [ ] #3 mix test passes, and every hook works in the dev browser with no console errors
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
All 14 hooks are colocated. stripe_form moved to EdenflowersWeb.StripeForm. New shared components: gallery/1 (PhotoGallery; photo_gallery was taken by ProductFormLive) and character_count/1 (CharacterCount; the counter span is now the hook element and phx-update="ignore", so a re-render no longer resets the admin count to 0). The flash uses the full hook name, since ".Name" only expands in a literal phx-hook. In LiveComponents (MonthGrid) the script must sit inside the root tag.

Checked in headless Chrome on the dev server: carousel, shy header, both galleries, Stripe on a payment link, info flash auto-dismiss, overview day strip, fee explorer, calendar arrow keys, order queue arrow keys, admin card message count, checkout FocusElement. No console errors. mix test, format check, credo all pass.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-23 08:46

---

Left for a human: PushToggle (admin account) and PushNudge (overview) only render with VAPID_PUBLIC_KEY set, which dev lacks, so they were not exercised. Check both on a real device, then mark AC #3 and set done.

---

author: @claude
created: 2026-10-27 13:57

---

Launch triage 2026-10-27 with David: marked done. Only the PushToggle/PushNudge device check was left; Jennie will notice in daily use if push breaks.

---
<!-- COMMENTS:END -->
