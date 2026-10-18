---
id: TASK-18.3
title: Split subscription management out of the account page
status: ready-for-agent
assignee: []
created_date: '2026-10-18 03:08'
labels: []
dependencies: []
parent_task_id: TASK-18
type: refactor
ordinal: 54000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
### Problem

`EdenflowersWeb.AccountLive` is 1,333 lines: account details, the email-change code flow, newsletter toggle, the order and course timeline, customer cancellation, and the whole subscription manager (`manage_drawer`, `subscription_payment`, `next_delivery`, `detail_row`, and the pause, resume, cancel, edit and change handlers). `SubscriptionCardLive` already handles the card replacement on its own.

### What to build

- Subscription management in its own LiveComponent (or LiveView, if it reads better with its own route), owning its drawer, form and handlers. `AccountLive` renders it per subscription and refreshes on its messages.
- Optionally the email-change flow as a second component, if `AccountLive` is still long after the first split.
- No behaviour or copy changes.

### Tests

- The existing account page tests pass, adjusted only for element ids if the component changes them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `AccountLive` no longer holds any subscription handler
- [ ] #2 The existing suite passes
<!-- AC:END -->
