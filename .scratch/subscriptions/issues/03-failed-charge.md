# Handle a failed off-session charge

Status: ready-for-agent

## Parent

`.scratch/subscriptions/spec.md`

## What to build

When the off-session charge for an occurrence is declined or needs authentication, the order is still placed: Jennie has committed to it, see ADR 0001. It is flagged unpaid, and the customer is emailed a Payment Link for it. The subscription moves to `payment_failed` and creates no further occurrences until the customer pays or updates their card. Paying the link reactivates it.

## Acceptance criteria

- [ ] On `authentication_required` or a card decline, the occurrence is placed unpaid with a Payment Link opened, and the customer gets an email with the link.
- [ ] The subscription becomes `payment_failed` and the occurrence trigger skips it.
- [ ] When the Payment Link payment succeeds (existing webhook/reconcile path), the subscription returns to `active`.
- [ ] Admin subscription list shows `payment_failed` clearly.
- [ ] Tests use the Stripe mock for both error codes and the recovery.

## Blocked by

- `02-create-occurrences.md`
