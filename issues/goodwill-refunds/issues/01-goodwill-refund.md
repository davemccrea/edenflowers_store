# Give a goodwill refund on a fulfilled order or a booking

Status: needs-info
Type: feature

## What to build

The whole spec: decisions 1 to 4.

- `goodwill` on `Payment` (generated migration), left out of `amount_paid` for the balance but counted by `refunded?`.
- A fragment action for Jennie's goodwill refund outside Stripe, and a `Payments` function that refunds an amount through Stripe and lets the webhook record it as goodwill.
- `record_stripe_refund` marking the part beyond what was owed back as goodwill.
- The "Refund" form in the order menu and the booking menu; order log and payments list labels.
- CONTEXT.md: add **Goodwill refund**. The payment-balance spec's decision 3 gets a pointer here.
- New copy through gettext, with en, fi and sv msgstrs.

## Tests

- Fragment, for both: a part and a full goodwill refund on a settled record leave it settled; the full one reads refunded; one above what was received, or above `paid_outside_stripe` outside Stripe, is refused; one while something is to collect is refused; it can be undone.
- Stripe: a webhook refund on a settled record is goodwill and leaves it settled; one straddling what was owed back settles the owed part and marks the rest goodwill; the goodwill refund through Stripe sends the right amount spread over the Stripe payments.
- LiveView, on both pages: "Refund" shows only when allowed, and a part refund by Stripe and by cash each record and leave no "To collect".

## Acceptance criteria

- [ ] Every case above passes
- [ ] A fulfilled order refunded in the Stripe dashboard doesn't appear under "To collect" on the Overview
- [ ] The existing suite passes

## Comments

- Before building: decide whether a goodwill refund asks for a reason shown in the order log (spec, open question). Set to `ready-for-agent` once decided.
