---
id: TASK-173.3
title: Mark expenses paid from matching bank payments
status: done
assignee: []
created_date: '2026-11-04 17:44'
updated_date: '2026-11-04 18:10'
labels: []
dependencies:
  - TASK-173.2
parent_task_id: TASK-173
type: feature
ordinal: 334000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** a supplier invoice Jennie scheduled in her bank should land in the VAT month it was actually paid, without her marking it.

- Expense gains `reference_number` (string, nullable). Claude extracts it on ingest (Finnish viitenumero or RF reference, as printed); Jennie can correct it in the detail form. Add it to `ingest`'s accept and upsert_fields, and to `correct`'s accept. No backfill of existing expenses. Generate the migration with `mix ash.codegen`.
- A scheduled AshOban action every 6 hours, a no-op without the Enable Banking config or a connected bank: reads booked debit transactions since the later of `connected_at` and the last successful sync (with a few days' overlap), for each linked account.
- A transaction marks an unpaid or scheduled expense paid on its booking date when reference numbers match ignoring spaces and the amount and currency match to the cent. Several matches or a different amount are skipped. A scheduled expense (future `paid_on`, from 59e72128) gets the booking date in place of the planned one, so a payment the bank moved past a weekend lands in the right month.
- Put the matching in an Ash action on Expense, not in the worker.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Claude's extraction fills reference_number, and Jennie can edit it
- [x] #2 A booked payment with matching reference, amount and currency marks the expense paid on its booking date
- [x] #3 A payment whose amount differs, or that matches several expenses, leaves them unpaid
- [x] #4 The sync does nothing when Enable Banking isn't configured or no bank is connected
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Expense.reference_number, stored normalized (Payments.ReferenceNumber.normalize: no spaces, upper case, Finnish leading zeros dropped). Claude extracts it; editable on the expense page. Bank.Connection :sync_payments (AshOban, 0 */6 * * *) runs Bank.Actions.SyncPayments: reads BOOK transactions from the later of the connection date and 14 days ago, and calls Expense :settle_from_bank for each outgoing one with a reference. That settles exactly one unpaid or scheduled expense with the same reference, amount and currency, setting paid_on to the booking date. The not-configured guard is one line and untested; the no-connection and expired cases are tested.
<!-- SECTION:NOTES:END -->
