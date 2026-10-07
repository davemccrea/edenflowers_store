# Subscriptions create ordinary orders

A Subscription is a schedule and a template, kept here rather than in Stripe Billing. Stripe only holds the card: the first checkout's PaymentIntent saves it to a Stripe Customer for off-session use, and before each delivery we copy the Subscription into an ordinary placed Online Order, its Occurrence, and charge that card for it.

Stripe Billing would own the dates and the price, and invoice on its own clock. Ours would then have to follow its webhooks, two calendars could disagree about when Jennie delivers, and closed days, skips and current prices would all be rules split across both. Keeping the schedule here leaves one source of truth for dates, and every Occurrence is an order like any other.

## Consequences

- Fulfilment views, emails, receipts, VAT, sales figures and refunds work on Occurrences unchanged, and each charge is a `Payment` row (ADR 0002).
- Each Occurrence is priced when it is created: the variant's current price and the delivery fee for the saved address.
- A declined or authentication-required charge leaves an Occurrence placed but unpaid, which Jennie already sees flagged (ADR 0001), with a Payment Link for the customer.
- Retrying, skipping and pausing are ours to build; Stripe does not dun or retry for us.
