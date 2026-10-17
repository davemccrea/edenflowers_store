# In-person refunds can't be recorded on cancelled orders

Status: ready-for-agent
Type: bug

## What to build

`CONTEXT.md` says a cancelled order paid in person "goes through Jennie": she hands the money back in cash, MobilePay or on Zettle. But `record_in_person_payment` refuses cancelled orders (`validate attribute_does_not_equal(:fulfillment_status, :cancelled)`), so that refund can't be recorded. The order keeps showing as paid, and the monthly report would count income that was handed back.

- Allow `record_in_person_payment` on a cancelled order **when the amount is negative**. A positive payment on a cancelled order stays refused, so Jennie can't take new money for an order that won't be made.
- Don't refund more than was paid in person: the refund can't take the order's in-person total below zero.
- The order detail page shows the in-person form on cancelled orders that still hold in-person money, as a refund form. Copy through gettext; clear fuzzy msgstrs in en, fi and sv.

## Acceptance criteria

- [ ] Jennie can record a negative in-person payment on a cancelled order
- [ ] A positive in-person payment on a cancelled order is still refused
- [ ] A refund larger than the in-person money taken is refused
- [ ] Tests cover all three

## Blocked by

None - can start immediately
