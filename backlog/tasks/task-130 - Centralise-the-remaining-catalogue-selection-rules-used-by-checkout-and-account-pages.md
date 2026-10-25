---
id: TASK-130
title: >-
  Centralise the remaining catalogue-selection rules used by checkout and
  account pages
status: needs-triage
assignee: []
created_date: '2026-10-25 14:15'
labels:
  - spec
  - developers
dependencies: []
references:
  - lib/edenflowers/catalog/product.ex
  - lib/edenflowers_web/features/account/account_live.ex
  - lib/edenflowers_web/features/admin/order_form_live.ex
  - lib/edenflowers_web/features/account/subscription_manager.ex
priority: low
type: refactor
ordinal: 252000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Pages obtain their business-specific catalogue selections from named resource reads or relationships rather than rebuilding eligibility filters in the web layer.

**Why:** Subscribable products, ordinary order-line variants and selectable subscription sizes are domain definitions. Keeping their filters in pages leaves more places to change when availability rules change.

Review evidence: AccountLive.assign_subscription_path builds subscribable == true on the store read although Product.:subscribable already exists. OrderFormLive.variant_options excludes the cards category in its own query. SubscriptionManager.size_options filters draft variants while retaining the currently selected size.

Reuse the existing subscribable read. Move the other actual eligibility selections into narrowly named resource reads/relationships and expose domain interfaces, preserving current ordering, visibility and the selected-variant exception. Keep translated labels, paths and formatting in the web layer.

The original review also mentioned CourseDetailLive splitting bookings into display groups. TASK-121 explicitly permits list splitting for display, so that split alone is not a violation and is not work for this ticket. Move only genuine business eligibility filters; do not turn harmless presentation grouping into extra resource actions.

Related: TASK-121 and completed TASK-19.5. Triage the precise remaining filter sites before implementation; do not reopen already-completed query migrations or expand this into a repo-wide abstraction exercise.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The account empty-state subscription link uses Product.:subscribable via its domain interface rather than rebuilding that business filter.
- [ ] #2 Custom-order selectable catalogue variants and subscription selectable sizes come from named domain reads/relationships, preserving card exclusion, draft handling and the selected-size exception.
- [ ] #3 Web code retains presentation formatting/grouping only; no new generic query abstraction or duplicated eligibility predicate is introduced.
- [ ] #4 Targeted domain/UI tests verify the offered products/variants and preserve existing empty-state navigation and current-selection behaviour.
<!-- AC:END -->
