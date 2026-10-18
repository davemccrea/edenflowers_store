# Split subscription management out of the account page

Status: ready-for-agent
Type: refactor

## Problem

`EdenflowersWeb.AccountLive` is 1,333 lines: account details, the email-change code flow, newsletter toggle, the order and course timeline, customer cancellation, and the whole subscription manager (`manage_drawer`, `subscription_payment`, `next_delivery`, `detail_row`, and the pause, resume, cancel, edit and change handlers). `SubscriptionCardLive` already handles the card replacement on its own.

## What to build

- Subscription management in its own LiveComponent (or LiveView, if it reads better with its own route), owning its drawer, form and handlers. `AccountLive` renders it per subscription and refreshes on its messages.
- Optionally the email-change flow as a second component, if `AccountLive` is still long after the first split.
- No behaviour or copy changes.

## Tests

- The existing account page tests pass, adjusted only for element ids if the component changes them.

## Acceptance criteria

- [ ] `AccountLive` no longer holds any subscription handler
- [ ] The existing suite passes

## Comments
