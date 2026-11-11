---
id: TASK-189
title: >-
  Turn the Elixir Balance calculations back into expressions if the stored total
  makes them cheap
status: done
assignee: []
created_date: '2026-11-11 09:26'
updated_date: '2026-11-11 10:16'
labels:
  - spec
  - developers
dependencies:
  - TASK-188
references:
  - docs/adr/0007-elixir-calculations-for-unqueried-money-booleans.md
priority: low
type: refactor
ordinal: 355000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Once TASK-188 stores a placed order's grand total, measure whether the calculations ADR 0007 moved to Elixir (`to_collect?`, `to_refund?`, `unpaid?`, `refundable?`, `receipt_available?`, `payment_instruction`, from ca89e74c, 2bd44acc, f3c58743) still cost a measurable amount on the admin order read and the Overview mount. If not, turn them back into expressions.

**Why:** The Elixir copies restate `settled?` and `payable?`, so a rule change has to be made twice, and they can't be filtered on. ADR 0007's default is an expression; they were moved only because of the Balance chain's cost.

Measure on a production dump the way TASK-188's handoff describes (`:timer.tc` medians over 30 runs, SQL size through `[:edenflowers, :repo, :query]` telemetry), before and after. Revert only those that make no measurable difference, and update ADR 0007's revision section with the result.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 The admin order read and the Overview mount are measured on a production dump with each calculation as an expression and in Elixir
- [x] #2 Each calculation that makes no measurable difference is an expression again, and ADR 0007 records what was measured
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Measured on the 2026-11-11 production dump with TASK-188's stored total in place. Method: medians of 30, SQL size through repo telemetry, and OrderDetailLive/OverviewLive `mount/3` called directly. With all the Elixir calculations as expressions, the Overview mount was unchanged (18.5 ms), but five admin order page mounts went from 121 to 156 ms and from 156 to 199 KB of SQL. Measured one at a time, only the booking's `cancelled_unsettled?` and `paid?` made no measurable difference, so those two are expressions again. The rest stay in Elixir. ADR 0007 lists each one with what it cost. The Invoice calculations weren't measured, because the stored total doesn't change their chain.
<!-- SECTION:FINAL_SUMMARY:END -->
