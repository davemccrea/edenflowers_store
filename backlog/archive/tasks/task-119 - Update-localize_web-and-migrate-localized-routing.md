---
id: TASK-119
title: Update localize_web and migrate localized routing
status: done
assignee: []
created_date: '2026-10-25 06:55'
updated_date: '2026-10-27 13:57'
labels:
  - developers
  - wontfix
dependencies: []
priority: low
type: chore
ordinal: 235000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Update localize_web to the latest compatible release and adapt the shop’s localized routing and layout helpers.

**Why:** Keep dependency maintenance unblocked without breaking language switching, authentication, or search-engine language annotations.

Dependency update commit 301bf0d5 temporarily narrowed localize_web to ~> 1.1.0. Attempting 1.3.0 failed because the newly imported Localize.VerifiedRoutes.hreflang_links macro clashes with EdenflowersWeb.Layouts.hreflang_links/1. The release also warns that localized LiveViews must use localize_live_session/3; current public routes are inside ash_authentication_live_session :public.

Resolve the helper-name collision and migrate localized LiveViews using a session structure compatible with Ash authentication and the existing maintenance, locale, current-path, order, and line-item hooks. Preserve nonlocalized checkout/account/payment routes and existing URLs. Review upstream 1.2/1.3 breaking changes; localize itself is already updated to 1.4.0.

Open for triage: agree on how localized sessions integrate with Ash authentication and which language-navigation behavior to cover before implementation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 localize_web is updated and the temporary ~> 1.1.0 restriction is removed or raised appropriately.
- [ ] #2 Compilation with warnings-as-errors passes without the hreflang helper collision or localized live-session warnings.
- [ ] #3 Regression tests verify language switching, authenticated and anonymous public navigation, and nonlocalized checkout/account/payment routes with existing hooks preserved.
- [ ] #4 Canonical and hreflang annotations remain correct for localized pages.
- [ ] #5 mix precommit passes.
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-10-27 13:57

---

Launch triage 2026-10-27 with David: closed. The ~> 1.1.0 pin works and only developers notice. Reopen if an upstream fix becomes necessary.

---
<!-- COMMENTS:END -->
