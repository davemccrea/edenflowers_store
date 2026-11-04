---
id: TASK-173.3
title: Mark expenses paid from matching bank payments
status: ready-for-agent
assignee: []
created_date: '2026-11-04 17:44'
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
- A transaction marks an unpaid expense paid on its booking date when reference numbers match ignoring spaces and the amount and currency match to the cent. Several matches or a different amount are skipped.
- Put the matching in an Ash action on Expense, not in the worker.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Claude's extraction fills reference_number, and Jennie can edit it
- [ ] #2 A booked payment with matching reference, amount and currency marks the expense paid on its booking date
- [ ] #3 A payment whose amount differs, or that matches several expenses, leaves them unpaid
- [ ] #4 The sync does nothing when Enable Banking isn't configured or no bank is connected
<!-- AC:END -->
