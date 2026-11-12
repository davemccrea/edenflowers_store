---
id: TASK-194
title: Offer a customer only the subscription actions the subscription allows
status: needs-triage
assignee: []
created_date: '2026-11-12 06:22'
updated_date: '2026-11-12 06:38'
labels:
  - spec
  - developers
  - quick
dependencies: []
references:
  - lib/edenflowers/orders/subscription.ex
  - lib/edenflowers_web/features/account/subscription_manager.ex
  - lib/edenflowers_web/features/admin/subscription_detail_live.ex
priority: low
type: refactor
ordinal: 359000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The pause, resume and cancel buttons on a customer's account read the same calculations the subscription's actions validate against.

**Why:** The customer page decides which buttons to show from the subscription's `state`, while the actions and the admin page use `pausable?`, `resumable?` and `cancellable?`. They agree today. If one of those calculations changes, the account page will offer a button the action refuses. CLAUDE.md asks for the UI and the action to read the same calculation.

## Problem

`Subscription` has `pausable?`, `resumable?`, `cancellable?` and `plan_changeable?` (`subscription.ex:254-281`). The actions validate against them (`subscription.ex:388, 397, 422, 451`) and the admin page reads them (`subscription_detail_live.ex:81-110`). The `:mine` read loads only `changeable?` and `changes_closed?`, so `subscription_manager.ex` re-derives the rest:

- pause or resume by `state == :active` (`subscription_manager.ex:510-514`)
- cancel shown on `state != :cancelled` (`:499`, `:531`)

The other `state` matches in that file choose copy per state. That is presentation and stays.

## What to build

Load `pausable?`, `resumable?` and `cancellable?` in the `:mine` read and have the three buttons read them.

## Still to decide

- Nothing known. Check when picking it up that the calculations give the same answer as the current `state` checks for every seeded subscription state, so no button appears or disappears for customers.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The account page shows pause, resume and cancel from pausable?, resumable? and cancellable?, and no longer gates them on state
- [ ] #2 For each subscription state, the account page offers the same buttons as before
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-12 06:38

---

Not dispatched (Ponytail review of the plan, 2026-11-12): pausable?, resumable? and cancellable? are state == :active, state == :paused and state in [:active, :paused, :payment_failed] (subscription.ex:678-691), and the account page's buttons already match them exactly. Nothing a customer sees would change. Do it in passing next time subscription_manager.ex is edited, or archive as wontfix. David has not chosen between those.

---
<!-- COMMENTS:END -->
