---
id: TASK-191
title: 'Compose each customer email once, for both its send and its preview'
status: needs-triage
assignee: []
created_date: '2026-11-12 06:22'
labels:
  - spec
  - developers
dependencies: []
references:
  - docs/adr/0005-emails-are-sent-once-by-a-queued-job.md
  - docs/adr/0006-one-customer-email-per-job.md
  - lib/edenflowers/email/preview.ex
  - lib/edenflowers/orders/order/emails.ex
  - lib/edenflowers/payments/changes/cancel.ex
  - test/edenflowers/email/preview_test.exs
priority: medium
type: refactor
ordinal: 356000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The preview Jennie sees in an email drawer is built by the same code that builds the email the customer gets, for every email she can send by hand.

**Why:** ADR 0006 promises Jennie a live preview of what the customer will get. For most emails that promise is kept by hand: `Email.Preview` and the email's send change each hold their own copy of what to load, which builder to use, the payment link URL and what to attach. Both files change often (17 commits each in the last 300), so the copies can drift and the preview can show something the customer never receives.

## Problem

Composing an email means: load the record, pick the builder, work out the payment link URL, decide the attachments. Each is written in the send change and again in `lib/edenflowers/email/preview.ex`.

- **Load lists, two copies each**
  - Order details: `preview.ex:142-151` (`totals_load`) and `send_order_details_email.ex`. The send's list also has `:payable?` and `:cancelled?`.
  - Gift voucher: `preview.ex:134-135` and `SendReceiptEmail.load_for_send`.
  - Receipt: `preview.ex:139` and `SendPaymentReceivedEmail.load_for_send`.
  - Booking emails: `preview.ex:187-198` and `load_for_send` in `send_confirmation_email.ex` and `send_payment_link_email.ex`.
- **Builder choice, two copies each**
  - Neutral receipt or Payment received: `preview.ex:227-236` decides by "is an Order and no amount typed"; the send decides by the `email: :receipt` option (`emails.ex:246`).
  - A voucher sale gets the voucher email: `preview.ex:164` and the `where:` clauses at `emails.ex:206-210`.
  - Delivered or Left at the door: `preview.ex:175-179` and `email/1` in `send_fulfillment_email.ex`.
  - Receipt attached to a booking confirmation only when money was received: `preview.ex:200-206` and `deliver/2` in `send_confirmation_email.ex`.
- **Payment link URL, three copies**: `preview.ex:239-242`, `payment_link_url/3` in `send_order_details_email.ex`, and `send_payment_link_email.ex`.

The doc on `SendPaymentReceivedEmail.email/2` states the hidden precondition: "the caller must load `record` as this change does".

`test/edenflowers/email/preview_test.exs` asserts preview equals sent for cancellation, refund and manual booking confirmation only. Order details, order updated, payment reminder, gift voucher and fulfillment have no parity test (found by test names and grep, not by reading every test body).

## What to build

Each email's send change owns one compose step (load, builder, URL, attachment names) and exposes it. The send adds only PDF generation, delivery and stamping. `Email.Preview` shrinks to turning what Jennie has typed so far into inputs and calling that compose step with stand-in attachments. It keeps the entered-order special cases (`build_entered`, `build_entered_booking`).

No new module. Part of this already exists and is the model: `Preview` reuses `Cancel.money/2` and `Cancel.load/0`, `SendReceiptEmail.gift_voucher_email/1`, `SendPaymentReceivedEmail.email/2`, `SendInvoice.load_for_email/1` and `SendSubscriptionCancelledEmail.load_for_send/1`. The remaining kinds follow the same shape.

ADR 0005 (queued job) and ADR 0006 (one email per job) are untouched.

## Still to decide (grill before implementing)

- The shape of the compose step each change exposes. Not designed yet, on purpose.
- Whether all email kinds move in one go or one kind per subtask.
- Whether the per-kind preview tests in other files are deleted once the parity test covers them.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 For every email Jennie can send from a drawer, on orders and on course bookings, the preview and the sent email come from the same compose code: no load list, builder choice, payment link URL or attachment rule appears in both Email.Preview and a send change
- [ ] #2 One table-driven test asserts that the preview equals the sent email for every hand-sent email kind on both resources
- [ ] #3 mix print_emails output is unchanged in en, sv and fi
<!-- AC:END -->
