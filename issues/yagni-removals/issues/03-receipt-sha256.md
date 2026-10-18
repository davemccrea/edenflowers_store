# Drop receipt_sha256, unless it's kept as evidence

Status: ready-for-human
Type: chore

## Problem

`Order.receipt_sha256` and `CourseRegistration.receipt_sha256` are written whenever a receipt is emailed (`Orders.Changes.SendConfirmationEmail`, `Courses.Changes.SendConfirmationEmail`, via `Receipt.sha256/1`) and never read: no page, check or export uses them. `Receipt`'s moduledoc says the PDF bytes aren't stored and the hash "records what was sent".

## Decide first

Is the hash ever going to be checked: by the accountant, in a dispute, or to prove which receipt a customer got? Receipts can be regenerated from the order, but a regenerated one reflects the order as it is now (an edit since changes it), so the hash is the only proof of the sent version's content.

- **Not needed:** do the removal below.
- **Needed:** keep both columns, and replace the moduledoc line with a comment on each attribute saying who would check it and how. Set this ticket to `wontfix`.

## What to build (if removing)

- Remove `attribute :receipt_sha256` from both resources and generate the migration with `mix ash.codegen remove_receipt_sha256`.
- Remove the `receipt_sha256` writes from both `SendConfirmationEmail` changes, `Receipt.sha256/1`, and the moduledoc line.
- `test/edenflowers/orders/changes/send_confirmation_email_test.exs`: drop the `receipt_sha256` assertion; keep the `receipt_emailed_at` one.

## Acceptance criteria

- [ ] `grep -r receipt_sha256 lib test` finds nothing outside migrations
- [ ] The existing suite passes

## Comments

- Needs the owner's answer to "Decide first". Set to `ready-for-agent` if removing.
