---
id: TASK-190
title: 'Store an order''s amount paid, held and invoiced so reads stop rebuilding them'
status: done
assignee: []
created_date: '2026-11-11 12:21'
updated_date: '2026-11-11 13:15'
labels:
  - spec
  - admin
  - developers
  - wontfix
dependencies: []
references:
  - docs/adr/0007-elixir-calculations-for-unqueried-money-booleans.md
  - lib/edenflowers/payments/payable.ex
  - lib/edenflowers/payments/payment.ex
  - lib/edenflowers/payments/invoice.ex
  - lib/edenflowers/orders/order.ex
  - lib/edenflowers/orders/line_item/changes/refresh_placed_order.ex
priority: medium
type: feature
ordinal: 356000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Store `amount_paid`, `amount_held` and `amount_invoiced` as columns, kept in step where a `Payment` is recorded and where an invoice is issued or credited, so `balance` and everything built on it is column arithmetic instead of three aggregates rebuilt at every reference.

**Why:** Opening an order in the admin still takes about 140 ms in production, most of it Ash planning the read rather than Postgres running it. Jennie feels that on every order she opens, and each new calculation over the Balance makes it worse.

## What was measured (2026-11-11, dev database, laptop, one warm `get_order_for_admin`)

- The read builds 254 aggregate queries for 15 distinct aggregates. `amount_held` is built 51 times, `amount_invoiced` 45, `amount_paid` 31: 127 of the 254.
- The rest of the top five are `gift_voucher_sale?` (43) and `free_delivery?` (37). They are not part of this spec; see "Left out".
- The read takes about 17 ms with protocols consolidated (22 ms in dev, where `mix.exs` turns consolidation off) and runs 13 queries.
- The time this spec saves has not been measured. Only the count of rebuilt aggregates has.

## Decisions (2026-11-11: Claude's recommendations, accepted by David)

- **Columns replace the aggregates, under the same names.** `amount_paid` and `amount_held` become attributes in the `Payable` fragment (non-null, default 0, scale 2). `amount_invoiced` becomes an attribute on `Order`; a booking keeps its `expr(0)`. Every reader keeps working unchanged. No `stored_*` twin: the sums have fifty-odd readers, and a twin invites reading the wrong one.
- **Course bookings too.** They get the columns by the attributes living in `Payable`, so both payables keep reading the same.
- **Payments: one write path.** Every `Payment` is created through `Payment.record` (called from `Changes.RecordPayment`, `Changes.PayFromVoucher`, `Changes.Cancel` and `Changes.RecordInvoicePayment`). A change on that action updates the parent order or booking in the same transaction. An invoice payment carries only `invoice_id`, so it touches neither.
- **Recompute, don't increment.** The change sets each column to the sum over the parent's payments (`amount_paid` leaving out goodwill), so one missed write heals at the next payment instead of staying wrong.
- **Invoices: two write paths.** `amount_invoiced` changes when an invoice is issued (`Invoice.issue`) and when a Credit note is created for it. Each recomputes the order's column from its invoices where `covers_order?`.
- **Other write paths:** none was found in `lib/`, and none is assumed. Start by searching `lib/`, `priv/repo` and the `justfile` for anything that creates, edits or deletes a `Payment`, an invoice or a Credit note another way, and cover what turns up. The backfill check in the acceptance criteria catches what the search misses.
- **Migration:** add the columns, backfill from the current sums. No check constraint: the columns are non-null.
- **Drift:** a test asserts column == sum over rows after every action that records a payment, issues an invoice or credits one. Only `Ash.Seed` and raw SQL get past the change.
- **Measure before merging.** Time the admin order read before and after on the same production dump. If the median improves by less than 3 ms (the noise TASK-189 measured), don't merge: record the numbers in ADR 0007 and close this as `wontfix`.
- **ADR 0007** gets a second revision recording this, and the Elixir calculations it lists are measured again afterwards, as TASK-189 did.

## Left out

- `paid_outside_stripe`, `paid_by_voucher`, `paid_through_stripe`: built once each per read.
- `gift_voucher_sale?` and `free_delivery?`: 80 builds between them, but both are read on carts too, where lines change freely, so storing them means maintaining them on every line change. Worth a spec of its own once this one is measured.
- The Balance itself: with its inputs stored it is column arithmetic, so a stored Balance gains little and adds a fourth thing to keep in step.
- Course bookings' `total_due`: already cheap (TASK-188).
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The admin order read is timed before and after on the same production dump (medians of 30, protocols consolidated), with the count of aggregate queries built, and the numbers are recorded in ADR 0007
- [x] #2 amount_paid, amount_held and amount_invoiced are read from columns: one admin order read builds no aggregate query for any of them
- [x] #3 Recording a payment, refund, goodwill refund, undo, voucher payment or cancellation refund leaves the order's or booking's columns equal to the sums over its payments, asserted by a test for each action
- [x] #4 Issuing an invoice and crediting one leave the order's amount_invoiced equal to the sum over its covering invoices, asserted by a test
- [x] #5 The migration backfills every existing order and booking, and a check on the production dump finds no row whose column differs from its sum
- [x] #6 Filters and sorts on settled?, payable?, payment_status and payment_link_open? return the same rows as before on the production dump
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-11 13:00

---

Deploy step: the migration backfills before traffic swaps, so a payment taken by the old code in that gap is not counted. Deploy this release in maintenance mode (just maintenance), then compare each order's and booking's stored amounts with the sums over its payments and covering invoices on production and expect no difference.

---

author: @claude
created: 2026-11-11 13:15

---

Built, measured and not merged (2026-11-11); the branch was deleted. It worked: five admin order reads went 88.7 → 74.0 ms on the production dump, and every filter, sort and amount came back identical. But it made the code worse for a saving nobody would feel (about 25 ms per order page in production). Unlike the grand total (TASK-188), which nothing changes once an order is placed, these three sums change with every payment, invoice and credit note. Storing them meant recomputing under a row lock on each write, a deploy in maintenance mode, a rule written twice in `Validations.Payable`, and a trap: `Ash.load` stops refreshing them, so any code reloading after a write must re-read the row or read stale money silently. The first version also had a race the review caught. Recorded in ADR 0007 under Considered Options. The acceptance criteria are ticked because the branch met them, not because anything landed.

---
<!-- COMMENTS:END -->
