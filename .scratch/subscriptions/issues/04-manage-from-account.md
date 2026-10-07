# Skip, pause and cancel from the account page

Status: ready-for-agent

## Parent

`.scratch/subscriptions/spec.md`

## What to build

A signed-in customer sees their subscriptions on the account page: size, interval, next delivery date and state. They can skip the next delivery, pause and resume, or cancel. Jennie can do the same from the admin subscription list.

Changes close 24 hours before the next occurrence is created, which is `lead_days` before the delivery date, so a change always lands before the card is charged.

## Acceptance criteria

- [ ] Account page lists the user's subscriptions; a user can't see or act on anyone else's (policy test).
- [ ] Skip adds the next date to `skipped_dates`; pause stops occurrences; resume sets the next date to the next future date on the schedule; cancel is final.
- [ ] Each action is refused inside the 24-hour cutoff, with a clear message.
- [ ] Admin can skip, pause, resume and cancel without the cutoff.
- [ ] All user-facing strings are translated (gettext sigils, sv/fi/en).
- [ ] Tests cover each action, the cutoff, and authorization.

## Blocked by

- `01-subscribe-at-checkout.md`
