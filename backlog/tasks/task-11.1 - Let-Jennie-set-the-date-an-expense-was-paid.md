---
id: TASK-11.1
title: Let Jennie set the date an expense was paid
status: ready-for-agent
assignee: []
created_date: '2026-10-17 07:07'
updated_date: '2026-10-18 07:28'
labels:
  - quick
dependencies: []
parent_task_id: TASK-11
type: feature
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** VAT is reported on a cash basis, so a supplier invoice paid in a later month lands in the wrong month without a paid date.

### What to build

The shop reports VAT on a cash basis, so an expense belongs to the month it was paid. A card receipt is paid on its date, but a supplier invoice may be paid in a later month. Give `Expense` a paid date Jennie can set for those. See decision 3 in `TASK-11`.

- **Attribute:** nullable `paid_on` (`:date`) on `Edenflowers.Expenses.Expense`.
- **Correcting:** add `paid_on` to the `correct` action's `accept` list.
- **Not ingested:** leave it out of `ingest`'s `accept` and `upsert_fields`, so re-processing a document never clears a date Jennie set. The LLM doesn't extract it; a receipt or invoice doesn't say when it was paid.
- **Detail form:** a "Paid on" date input in `ExpenseDetailLive` next to the existing date, with help text that it's only needed when the expense was paid on a different day from its date. Copy through gettext; clear any fuzzy msgstrs `gettext.merge` writes, in en, fi and sv.
- **Migration:** generate it with `mix ash.codegen`; don't write it by hand.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 An admin can set and clear "Paid on" on an expense, and it's saved
- [ ] #2 Re-ingesting the same Papra document leaves `paid_on` unchanged
- [ ] #3 The migration was generated from the resource
- [ ] #4 Tests cover setting `paid_on` through `correct` and it surviving `ingest`
<!-- AC:END -->
