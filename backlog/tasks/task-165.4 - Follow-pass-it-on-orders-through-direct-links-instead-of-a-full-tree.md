---
id: TASK-165.4
title: Follow pass-it-on orders through direct links instead of a full tree
status: done
assignee: []
created_date: '2026-11-10 07:27'
updated_date: '2026-11-10 07:35'
labels: []
dependencies: []
parent_task_id: TASK-165
type: refactor
ordinal: 352000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** Jennie can follow where a card came from and what it brought in without a large tree on every order page or recursive graph loading.

Agreed with David on 10 November 2026: replace the full tree with direct source-gift and redemption links, not extra buttons alongside the tree. Keep card codes and statuses and the link/remove-card workflow. Show every directly linked placed order, including cancelled ones with a Cancelled badge, so chains remain traversable through cancellations. Exclude carts. Each destination page offers its own direct neighbours; no full-chain overview or recursive loading.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Each order shows its immediate source gift, when linked, and every directly placed redemption of its own card, oldest first; no ancestors, grandchildren or sibling redemptions appear as direct links.
- [x] #2 Cancelled linked orders remain visible with a Cancelled badge; shopping carts are excluded and following links remains safe when historical links contain a cycle.
- [x] #3 Card codes, statuses, missing-source messaging and linking/removing cards remain available; external changes retain the warning-and-explicit-reload behaviour.
- [x] #4 Recursive tree loading/rendering is removed, affected tests and translation catalogues are updated, and focused domain/LiveView checks pass.
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Load only promotion.gift_order (with the existing committed? calculation) and the current pass_it_on_card's status and placed_orders in Order.Admin; sort Promotion.placed_orders by ordered_at then id. Remove Order.pass_it_on_chain and its calculation module.
2. Replace the recursive timeline with two flat sections, Source gift and Orders brought in, using the existing order text/card/status components and links. Retain card controls, incoming code/missing-source messaging, and cancellation badges.
3. Replace full-tree domain/UI tests with direct-neighbour, cancellation, cart exclusion, ordering and cycle cases. Preserve editor warning/reload checks.
4. Extract/review supported Gettext catalogues, run focused tests, format/catalogue checks and the UI detector, then inspect the live page on desktop and mobile when available. No database migration or storefront/email changes.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Verified with 72 passing tests across pass_it_on_links_test, order_detail_live_test, detail_refresh_test and payment_actions_test. Domain cases cover ordering/ties, cart exclusion, cancellations and cycles. LiveView cases verify only direct neighbours, missing/unplaced sources, cancelled badges, link/remove/status controls and warning-only external updates.

Browser check on existing development orders: followed Source gift and Orders brought in links in both directions. At 390px and 1440px the panel had no horizontal overflow; mobile links were 44px high. No development data was changed for the check. UI detector returned no findings; formatting, git diff --check and gettext.check passed; gettext.stats reviewed.

David requested usable, non-fuzzy Swedish translations for the new headings: Source gift = Gåvan kortet kom från; Orders brought in = Beställningar via kortet. Entries are marked AI-drafted with native review pending. Updated DESIGN.md to describe direct links instead of a full timeline. Full suite not run; changes remain uncommitted.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Replaced the pass-it-on tree with immediate source-gift and direct redemption links, retaining card code/status and controls. Cancelled placed orders remain linked and marked; carts and unplaced sources are not linked. Deleted the recursive calculation and renderer, reused existing relationships with stable redemption ordering, updated tests, supported translation catalogues and design guidance. Verified 72 focused tests, formatting/catalogue checks, UI detector and desktop/mobile browser navigation. No schema migration, storefront or email changes. Full suite and native Swedish review remain unverified.
<!-- SECTION:FINAL_SUMMARY:END -->
