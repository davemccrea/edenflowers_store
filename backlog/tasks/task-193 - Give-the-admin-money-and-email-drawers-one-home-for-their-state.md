---
id: TASK-193
title: Give the admin money and email drawers one home for their state
status: needs-triage
assignee: []
created_date: '2026-11-12 06:22'
labels:
  - spec
  - developers
dependencies: []
references:
  - docs/agents/ash-liveview-review.md
  - lib/edenflowers_web/features/admin/order_detail_live.ex
  - lib/edenflowers_web/features/admin/course_detail_live.ex
  - lib/edenflowers_web/features/admin/invoice_live.ex
  - lib/edenflowers_web/features/admin/payment_actions.ex
  - lib/edenflowers_web/features/admin/email_drawer.ex
  - lib/edenflowers_web/features/admin/drawer_preview.ex
  - lib/edenflowers_web/features/admin/drawers.ex
  - test/edenflowers_web/features/admin/balance_panel_test.exs
priority: medium
type: refactor
ordinal: 358000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The settlement, cancel and email drawers hold their own forms, preview and event handling, so the order page and the course page open them and are told when something changed.

**Why:** These are the most-changed files in the admin (`order_detail_live.ex` 33 commits in the last 300, `drawers.ex` 23, `course_detail_live.ex` 15). Every change to a drawer has to be made on each page that hosts it, and the two pages have already drifted apart.

## Problem

`PaymentActions`, `EmailDrawer` and `Drawers` share the forms and markup, but the state around them is written out in each page.

- **About thirteen handlers repeated on two pages**: `open_cancel`, `close_cancel`, `validate_cancel`, `submit_cancel`, `open_settlement`, `change_payment`, `record_payment`, `change_refund`, `refund`, `undo_payment`, `open_payment_link` and the four email events. Order page: `order_detail_live.ex:643-786`. Course page: `course_detail_live.ex:274-440`. The email four appear a third time at `invoice_live.ex:717-800`.
- **The shared modules' interface includes the page's assign names.** `PaymentActions.change_payment/4` returns `[payment_form:, preview:]` (`payment_actions.ex:63`), `change_refund/3` returns `[refund_form:, preview:]` (`:119`), and `EmailDrawer.open/close` write `email_form`, `email_kind` and `preview` into the caller's socket.
- **One `:preview` assign serves four drawers** (cancel, settlement, email, fulfillment), written from thirteen places across the two pages.
- **Each page initialises the same loose set of assigns**: `cancelling`, `cancel_form`, `payment_form`, `refund_form`, `settlement_mode`, `email_form`, `email_kind`, `preview` (`order_detail_live.ex:51-54`).
- **The pages already differ.** The order page builds a preview for both settle and refund (`order_detail_live.ex:687-700`); the course page only in refund mode (`course_detail_live.ex:274-293`).

## What to build

One stateful LiveComponent for the settlement, cancel and email drawers. It takes a payable and an actor, owns its forms, preview and handlers, and tells the page one thing: changed, reload. `PaymentActions`, `EmailDrawer` and `DrawerPreview` merge into it. The stale-editor notice from `docs/agents/ash-liveview-review.md` (it shows inside drawers too) carries over.

The actions underneath do not change. No ADR is affected.

## Still to decide (grill before implementing)

- One component for all three drawers, or one each.
- Whether the course page's missing settle preview is deliberate. If not, the component fixes it; if so, it needs a switch.
- Whether the invoice page's email drawer joins now or later, and whether the fulfillment drawer (order page only) is in scope.
- How flashes and the confetti on the order page are raised once the handler lives in the component.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The order page and the course page hold no event handlers or assigns for the settlement, cancel and email drawers beyond opening them and reloading when told something changed
- [ ] #2 The drawers' forms and preview are assigned in one module, and no shared helper returns or writes assigns by the page's names
- [ ] #3 balance_panel_test.exs still covers recording, refunding, undoing and cancelling for both orders and bookings, and passes
- [ ] #4 The stale-editor notice still shows inside each drawer
<!-- AC:END -->
