# Skip, pause and cancel from the account page

Status: resolved

## Parent

`.scratch/subscriptions/spec.md`

## What to build

A signed-in customer sees their subscriptions on the account page: size, interval, next delivery date and state. They can skip the next delivery, pause and resume, or cancel. Jennie can do the same from the admin subscription list.

Changes close 24 hours before the next occurrence is created, which is `lead_days` before the delivery date, so a change always lands before the card is charged.

## Acceptance criteria

- [x] Account page lists the user's subscriptions; a user can't see or act on anyone else's (policy test).
- [x] Skip adds the next date to `skipped_dates`; pause stops occurrences; resume sets the next date to the next future date on the schedule; cancel is final.
- [x] Each action is refused inside the 24-hour cutoff, with a clear message.
- [x] Admin can skip, pause, resume and cancel without the cutoff.
- [x] All user-facing strings are translated (gettext sigils, sv/fi/en).
- [x] Tests cover each action, the cutoff, and authorization.

## Blocked by

- `01-subscribe-at-checkout.md`

## Comments

**Built (slice 04)**

- `Subscription` actions `:skip`, `:pause`, `:resume`, `:cancel` and read `:mine`. Transitions: pause (active → paused), resume (paused → active), cancel (active, paused or payment_failed → cancelled). `extra_states` is gone because every state now appears in a transition.
- The cutoff lives in one place, the `changes_closed?` calculation: `state == :active and next_fulfillment_date <= Helsinki today + lead_days + 1`. It becomes true at Helsinki midnight on the day before the trigger can first pick the date up (the trigger's UTC midnight is 02:00/03:00 in Helsinki, so this is a little over 24 hours early, never late). `Validations.SubscriptionChangesOpen` refuses skip, pause and cancel when it's true, with the message "It's too late to change your next delivery.", and lets an admin actor through.
- Skip adds `next_fulfillment_date` to `skipped_dates`; it is idempotent and only allowed while active. The occurrence job already passes over it.
- Resume steps whole intervals from the stored `next_fulfillment_date` to the first date after today + `lead_days` (Helsinki), so the next date is never already inside the lead window. A date still far enough away is kept.
- Policies: the admin bypass now allows the four actions. Everyone else may run `:mine` and the four actions only where `user_id == actor.id`.
- Code interfaces: `list_my_subscriptions`, `get_subscription`, `skip_subscription`, `pause_subscription`, `resume_subscription`, `cancel_subscription`.
- Account page: a "Subscriptions" section, shown only when the customer has one. It shows the size and interval, then status: "Next delivery …", "Skipping …. Next delivery …", "Paused", "On hold until the last delivery is paid" or "Cancelled". Buttons: Skip next delivery and Pause (active), Resume (paused), Cancel subscription (anything not cancelled). Skip and cancel ask for confirmation. Inside the cutoff there are no buttons, only the cutoff message. If the cutoff passes while the page is open, the refused change flashes the same message.
- Admin `/admin/subscriptions`: an Actions column (Skip, Pause, Resume, Cancel), with no cutoff, and a "Skipped" note under the next date.
- 19 new strings, translated into sv and fi.
- Tests: `test/edenflowers/orders/manage_subscription_test.exs` (12 tests: own list only, forbidden on another user's subscription, each action, pause stops the scheduler, resume date both ways, cancel is final, payment_failed can be cancelled but not paused, the cutoff boundary, the cutoff refusing each action, the admin bypass, cancelling a paused subscription close to its old date). 7 tests in `account_live_test.exs`, 1 in `subscriptions_live_test.exs`.

**Decisions and deviations**

- A payment_failed subscription can be cancelled by the customer but not paused or skipped. Paying the link reactivates it; after a cancel, `ReactivateSubscription` leaves it cancelled. The unpaid Occurrence stays placed with its link open.
- The cutoff applies only to an active subscription. A paused or payment_failed one has no Occurrence coming, so cancelling it is always allowed, and resume isn't gated because it moves the date out of the lead window anyway. A resumed date can land inside the next cutoff (for example 4 days out), so the customer can't skip it straight away.
- Once the next date is skipped there is no "unskip" and no skipping the one after. The Skip button goes away until the job moves the date on.
- Cancelled subscriptions stay listed on the account page, marked "Cancelled".
- The customer sees sizes through `Admin.Components.variant_size_label/1`, reused rather than copied.

**Open questions**

- If the skipped next date is inside the cutoff, the customer sees "It's too late to change your next delivery." until the job moves the date on (at most a day or so), although that delivery won't happen anyway.
