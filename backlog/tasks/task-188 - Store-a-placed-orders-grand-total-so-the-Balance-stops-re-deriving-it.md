---
id: TASK-188
title: Store a placed order's grand total so the Balance stops re-deriving it
status: done
assignee: []
created_date: '2026-11-11 09:17'
updated_date: '2026-11-11 09:39'
labels:
  - spec
  - admin
  - developers
dependencies: []
references:
  - docs/adr/0007-elixir-calculations-for-unqueried-money-booleans.md
  - lib/edenflowers/payments/payable.ex
  - lib/edenflowers/orders/order.ex
  - lib/edenflowers/orders/order/changes/snapshot_vat_breakdown.ex
  - 'https://github.com/ash-project/ash/issues/1282'
priority: medium
type: feature
ordinal: 354000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Store a placed order's grand total as a column, snapshotted where `vat_breakdown` is, and have an order's `total_due` (and so `balance`) read it instead of re-deriving it from line items, promotion and fee rules.

**Why:** Admin navigation between orders and to the Overview feels slow (0.5–2 s). Production's CPU cores are about 5–6× slower than a dev laptop, and most of each read is Ash building the Balance chain's SQL in Elixir, not Postgres running it.

## Decisions (grilled 2026-11-11, recorded in ADR 0007's revision)

- **Where it's set:** `Changes.SnapshotVatBreakdown` sets it with `vat_breakdown` (checkout ×2, occurrences, `refresh_vat_breakdown` run by `place_custom` and `edit` via `RecordEnteredLineItems`). `sell_gift_voucher` sets `vat_breakdown: []` directly and never runs the snapshot, so it sets the stored total itself. Take it from the loaded live `grand_total`, not by summing the breakdown: `compute_breakdown` leaves out gift-voucher lines.
- **Only the grand total.** Not the fulfillment fee.
- **Carts:** `total_due` on an order reads the column, but carts have no stored total and checkout reads `voucher_amount`/`stripe_amount` (`Payable`) on the cart. Those read a total each resource defines: the live `grand_total` on an order, `total_due` on a course booking. Not `stored || live`: Ash would still inline the live branch.
- **Migration:** backfill every placed order from the live grand total, then a check constraint `state <> 'placed' OR <column> IS NOT NULL`, so a write path that misses it fails loudly.
- **Drift:** every input to the live total (`unit_price`, `quantity`, `discount_rate`, `promotion_minimum_cart_total`, line `free_delivery`, quoted fees, override) is already stored, so the column is a cache that only a write path skipping the snapshot can put out of step. A test asserts stored == live after every write path that places or changes a placed order. No periodic production check.
- **Courses:** `CourseRegistration.total_due` is already cheap, so this is orders only.
- **Elixir calculations:** reverting them to expressions is TASK-189, after measuring with this in place.
- The websocket round trip through Cloudflare was not measured first; build this anyway.

## Handoff: what the previous session found (2026-11-11)

### Measurements (production dump, `tmp/production-v1.30.2-20261111T091500.dump`)
- Postgres runs every order read in 1–2 ms (pg_stat_statements, enabled in v1.30.3). The time goes to Ash: tprof shows `Ash.Filter`, `Ash.Expr`, `Ash.Query` and `Enum` dominating.
- Production timings (rpc `:timer.tc`, v1.30.2): `get_order_for_admin` 225 ms, `list_unsettled_orders` 71 ms, `OrderDetailLive.mount` 296 ms. The same on the laptop: 41 / 15 / 47 ms. The server has 2 cores, 2 schedulers, no container CPU cap and is idle, so its cores are just slow.
- In-app navigation in `/admin` is one `live_session`, so it does a single connected mount. Only full loads mount twice. Loading only on the connected mount was considered and turned down for the order page.
- Laptop numbers after this session's commits: admin order read 41 → ~31 ms (30 KB → 21 KB SQL). Overview: unsettled orders 14 → 10 ms, due_soon 7 → 6 ms. One whole Overview mount ≈ 30 ms.

### Landed on main (not yet pushed or deployed)
- `e4891a9e` `:to_fulfil` no longer loads `payment_status` (the order page uses only ids): 10.6 → 1.5 ms.
- `4d8c720a` `balance` as `GREATEST(due - paid, 0) + LEAST(due - held, 0)` (a fragment, which relies on held ≤ paid). `payment_status` references `balance` once. A line item's `total` is `subtotal - discount`. ADR 0007 has a new consequence line about this.

### Why the chain is expensive
Ash inlines an expression calculation at every reference and never computes it once. Each `balance` still carries ~9 copies of the free-delivery fee subquery and ~5 line_items scans. They come from `total_due` appearing twice in `balance`, and from `promotion_applied?` (with an `items_subtotal` subquery) inside every line total. `balance` itself is never filtered, but `settled?` (overview/bookings unsettled, course `to_settle?`), `payable?` (email trigger `where`, atomic validation), `payment_link_open?` (subscriptions) and `payment_status` (inside `open?`, `customer_status`) are. So it has to stay SQL-capable.

### Ruled out
- More module calculations: the 11 unfiltered expression booleans on the order page cost about 2 ms combined.
- Ash combination queries (single-branch, `^combinations(:bal)`) work in AshPostgres, but they gave about 1 ms on this data and would mean writing the money rules again per query.
- Ash has no CTE or LATERAL reuse for calculations; ash-project/ash#1282 is the nearest open issue.
- Overview: dropping the "To collect" badge on day cards (~30 ms prod per mount) is moot once this lands.

### Tools
Benchmark scripts were in the previous session's scratchpad and are gone. To recreate them: restore the dump into a scratch DB (`createdb X && pg_restore --no-owner --no-privileges -d X <dump>`, then `delete from oban_jobs`), run `DATABASE_NAME=X PORT=<free> mix run script.exs`, and time with `:timer.tc` medians over 30 runs. Count SQL size by attaching `:telemetry` to `[:edenflowers, :repo, :query]`. A local DB `edenflowers_measure_prod` holding production customer data may still exist: drop it when done.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The user has been grilled on storing the total and whether to revert the earlier Elixir calculations, and the decision is recorded in an ADR
- [x] #2 The admin order read and the Overview mount are measured before and after on a production dump
- [x] #3 A test asserts the stored total equals the live grand total for placed orders after every write path that places or changes them
- [x] #4 Checkout on a cart charges the same amount as before: voucher_amount and stripe_amount read the live grand total on a cart, not the stored column
- [x] #5 sell_gift_voucher stores its total, and a check constraint refuses a placed order without one
- [x] #6 A migration backfills the stored total for every existing placed order from the live grand total
<!-- AC:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @claude
created: 2026-11-11 09:26

---

Grilled 2026-11-11 after a review of the proposal. Decided: build it (no websocket measurement first); checkout calculations in Payable read a per-resource total (live grand_total on an order) since carts have no stored total; sell_gift_voucher sets the stored total itself; backfill in the migration plus a check constraint on placed orders; no periodic production check, because every input to the live total is already stored, so only a write path skipping the snapshot can make them differ, and the invariant test covers that; store only the grand total, not the fulfillment fee; reverting the Elixir calculations is a separate follow-up after measuring. Recorded as a revision of ADR 0007.

---
<!-- COMMENTS:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
A placed order now stores its grand total in `orders.stored_grand_total`. `Changes.SnapshotVatBreakdown` sets it from the live `grand_total` when it sets `vat_breakdown`, and `sell_gift_voucher` sets it from its amount. `place_custom` inserts 0 until `RecordEnteredLineItems` refreshes it. `Order.total_due` reads the column. Each Payable resource defines `checkout_total` (the live `grand_total` on an order, `total_due` on a booking), and `voucher_amount`/`stripe_amount` read it, so checkout charges the same as before. Carts have no Balance: `payment_status` reads `pending` before placing, and `Validations.Payable` checks `checkout_total` on anything not yet committed.

The migration backfills placed orders from the live total through Ash. It skips the backfill when there are no placed orders, so later schema changes can't break a fresh database. Then it adds the check constraint `orders_placed_have_stored_grand_total`. On the 2026-11-11 production dump: 15/15 placed orders backfilled with stored = live, and on dev 37/37.

`assert_stores_live_grand_total/1` (DataCase) runs after finalize_checkout (with and without a Gift voucher line), place_paid_by_voucher, place_unpaid_occurrence, place_custom, edit and sell_gift_voucher. Test generators keep a seeded placed order's stored total in step as lines are added, and `seed_placed/2` places a seeded cart.

Measured on the dump (laptop, medians of 30): 5 admin order reads 130 → 96 ms, unsettled orders 9.7 → 4.3 ms, due soon 5.8 → 3.9 ms, admin list 13.2 → 10.5 ms. Recorded in ADR 0007.
<!-- SECTION:FINAL_SUMMARY:END -->
