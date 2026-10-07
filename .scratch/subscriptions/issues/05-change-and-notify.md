# Change size, frequency or card; set-up email

Status: ready-for-agent

## Parent

`.scratch/subscriptions/spec.md`

## What to build

From the account page, a customer can change their bouquet size and how often it comes, and replace their saved card. Replacing the card uses a Stripe SetupIntent with the Payment Element, the same element checkout uses. Replacing the card on a `payment_failed` subscription makes it `active` again. The customer gets a "your subscription is set up" email when it activates.

## Acceptance criteria

- [ ] Size and interval changes respect the 24-hour cutoff and apply from the next occurrence.
- [ ] Card update stores the new payment method; a `payment_failed` subscription returns to `active`.
- [ ] A set-up email is sent once on activation (Oban trigger, like the existing order emails).
- [ ] All user-facing strings are translated.
- [ ] Tests cover changes, card update (Stripe mock), and that the email is sent exactly once.

## Blocked by

- `03-failed-charge.md`
- `04-manage-from-account.md`
