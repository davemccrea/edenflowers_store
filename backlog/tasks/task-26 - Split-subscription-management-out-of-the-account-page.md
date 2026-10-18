---
id: TASK-26
title: Split subscription management out of the account page
status: done
assignee: []
created_date: '2026-10-18 11:35'
updated_date: '2026-10-18 14:20'
labels:
  - spec
  - developers
dependencies: []
priority: medium
type: refactor
ordinal: 81000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The account page renders one subscription manager per subscription instead of holding every subscription handler itself

**Why:** `AccountLive` is 1,333 lines, much of it subscription management, which makes the account page hard to read and change.

### Problem

`EdenflowersWeb.Account.AccountLive` holds account details, the email-change code flow, newsletter toggle, the order and course timeline, customer cancellation, and the whole subscription manager (`manage_drawer`, `subscription_payment`, `next_delivery`, `detail_row`, and the pause, resume, cancel, edit and change handlers). Per-subscription state (`edited_subscriptions`, `subscription_notice`) is threaded through the page by id. `SubscriptionCardLive` already handles the card replacement on its own.

### What to build

- A LiveComponent per subscription that renders the list row and its drawer (the drawer moves inside the `<li>`) and owns the change form and the pause, resume, cancel, edit and change handlers. Its `edited?` and notice are its own assigns, replacing the page-wide set and `notice_for`.
- After a change the component tells `AccountLive`, which reloads subscriptions and orders and rebuilds the timeline.
- No behaviour or copy changes, and no new route.

### Decisions

- LiveComponent, not a LiveView with its own route: a route would turn the drawer into a page.
- The email-change flow stays in `AccountLive`.

### Tests

- The existing account page tests pass, adjusted only for element ids if the component changes them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `AccountLive` no longer holds any subscription handler
- [x] #2 The existing suite passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Subscription row and drawer live in `EdenflowersWeb.Account.SubscriptionManager`, one LiveComponent per subscription. Events no longer carry a subscription id, so the forged-id test now checks that an id sent to the component is ignored.
<!-- SECTION:NOTES:END -->
