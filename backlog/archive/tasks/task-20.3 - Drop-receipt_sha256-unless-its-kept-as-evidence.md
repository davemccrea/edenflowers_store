---
id: TASK-20.3
title: 'Drop receipt_sha256, unless it''s kept as evidence'
status: done
assignee: []
created_date: '2026-10-18 03:31'
updated_date: '2026-10-18 08:17'
labels: []
dependencies: []
parent_task_id: TASK-20
type: chore
ordinal: 70000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
**Why:** The receipt hash is written on every receipt email and never read. It should go, or be documented as evidence.

### Problem

`Order.receipt_sha256` and `CourseRegistration.receipt_sha256` are written whenever a receipt is emailed (`Orders.Changes.SendConfirmationEmail`, `Courses.Changes.SendConfirmationEmail`, via `Receipt.sha256/1`) and never read: no page, check or export uses them. `Receipt`'s moduledoc says the PDF bytes aren't stored and the hash "records what was sent".

### Decide first

Is the hash ever going to be checked: by the accountant, in a dispute, or to prove which receipt a customer got? Receipts can be regenerated from the order, but a regenerated one reflects the order as it is now (an edit since changes it), so the hash is the only proof of the sent version's content.

- **Not needed:** do the removal below.
- **Needed:** keep both columns, and replace the moduledoc line with a comment on each attribute saying who would check it and how. Set this ticket to `wontfix`.

### What to build (if removing)

- Remove `attribute :receipt_sha256` from both resources and generate the migration with `mix ash.codegen remove_receipt_sha256`.
- Remove the `receipt_sha256` writes from both `SendConfirmationEmail` changes, `Receipt.sha256/1`, and the moduledoc line.
- `test/edenflowers/orders/changes/send_confirmation_email_test.exs`: drop the `receipt_sha256` assertion; keep the `receipt_emailed_at` one.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `grep -r receipt_sha256 lib test` finds nothing outside migrations
- [x] #2 The existing suite passes
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
The owner confirmed nobody will check the hash, so it was removed.
<!-- SECTION:NOTES:END -->

## Comments

<!-- COMMENTS:BEGIN -->
author: @david
created: 2026-10-18 03:31

---

- Needs the owner's answer to "Decide first". Set to `ready-for-agent` if removing.

---
<!-- COMMENTS:END -->
