# Create and charge each delivery

Status: ready-for-agent

## Parent

`.scratch/subscriptions/spec.md`

## What to build

A scheduled job turns each active subscription into an ordinary placed Online Order a few days (`lead_days`, e.g. 3) before its next delivery date. That order is an **Occurrence**. The job charges the saved card off-session and records the Payment. From then on the order behaves like any other: it shows in fulfilment, sends the confirmation email, and counts in sales. Then the subscription moves on to its next date.

This slice covers the happy path only. A failed charge is slice 03.

## Acceptance criteria

- [ ] Occurrences have a new order origin `:subscription` and link to their subscription; admin order views show a "Subscription" badge.
- [ ] The line item comes from the variant at its **current** price through the normal add-to-cart path, so the free-delivery flag is copied over. The delivery fee is priced as for any order, so it's 0 inside the free zone.
- [ ] Customer name and email are read from the user at creation time; recipient and delivery details come from the subscription.
- [ ] If the delivery date is a closed day for the delivery option (`Fulfillment.Availability`), the date moves to the next open day.
- [ ] Dates in `skipped_dates` create no order and just move the subscription on.
- [ ] The off-session charge uses a deterministic idempotency key (subscription + date). Re-running the job never creates a second order or charge.
- [ ] A failed HERE geocode or a Stripe network error leaves the job to retry. It does not cancel the subscription or advance its date.
- [ ] Tests cover the happy path, a closed-day roll-forward, a skip, and an idempotent re-run (`Oban.Testing`).

## Blocked by

- `01-subscribe-at-checkout.md`
