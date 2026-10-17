# Undo a payment, and keep the booking row compact

Status: done
Type: feature

## What to build

Follow-ups to 02 and 03, from the decisions left open when they shipped.

- `undo_payment` on the fragment (spec decision 3): records the opposite of a payment Jennie recorded, once, pointing at it. A refund while something is still to collect is now refused, since undo is how a mistake is corrected.
- "Undo" on each undoable payment in the order page's payments list, and in each booking's menu on the courses page. The order log reads "Undid".
- The courses page shows the balance panel only on a booking to refund, full width under its row; a booking to collect keeps the "To collect" badge and the quick form. The row wraps the form under the name when the card is narrow.
- The courses page lists past courses, marked past, while any booking on them is unsettled (`Course.admin_list`).
- The spec records `stripe_refund`, which shipped without being in it.

## Tests

- Fragment, for both: undoing a payment owes it again and isn't `refunded?`; undoing a refund owes it back again; a payment is undone once; a Stripe payment, an undo, or another record's payment can't be undone; a refund while something is to collect is refused.
- Policies: only the admin undoes a payment.
- LiveView, on both pages: undo, once; no undo on a Stripe payment. A booking to collect has the quick form and no panel. A past course with an unsettled booking is listed and marked past; a settled one isn't.

## Acceptance criteria

- [x] Every case above passes
- [x] The existing suite passes

## Blocked by

- 02, 03
