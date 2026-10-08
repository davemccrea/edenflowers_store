# Make the subscription status on /account tell the truth

Status: resolved

## Parent

`.scratch/subscriptions/spec.md`

## What to build

Audit items A2, A3, A7, A9, A14 and A16 in `10-ux-audit.md`. Each subscription row should say, in plain words, what happens next and when the customer pays.

## Acceptance criteria

- [x] **A2.** "Next delivery" (and the skip confirmation) uses the earliest upcoming placed order for the subscription when there is one, else `next_fulfillment_date`.
- [x] **A3.** Price with its unit and charge timing: "€60 per delivery, delivery included. Next delivery Friday 9 October, charged on Tuesday 6 October" (charge date = delivery date − `lead_days`).
- [x] **A7.** Paused reads "Paused. No deliveries or charges." plus "Resume now and your next delivery is …", computed with the `StepToScheduledDate` logic.
- [x] **A9.** Active, paused and payment-failed first; cancelled last with "Cancelled on …". Cancelled rows older than ~30 days are hidden.
- [x] **A14.** Every subscription date uses weekday + long date, matching how Orders formats dates.
- [x] **A16.** Inside the 24h cutoff, show "Need to change this one? Contact us." with a contact route.
- [x] Strings translated (sv, fi). Tests for each state's copy and the ordering.

## Blocked by

None.

## Comments

**Built (slice 12)**

- Next delivery: an upcoming booked Occurrence (placed, not cancelled, dated today or later) is shown in place of `next_fulfillment_date`. The drawer adds "The one after: …, charged on …".
- Charge timing: `Subscription.charged_on/1` (delivery minus `lead_days`). The table says "Charged 25 Oct"; the drawer says "Charged to your card on Sunday 25 October."
- Paused: "No deliveries or charges. Resume now and your next delivery is …", from `Subscription.resume_date/1`. That reuses `StepToScheduledDate.scheduled_date/3`, now public and shared with the change.
- Order: cancelled last (sorted in the LiveView). `:mine` drops cancelled subscriptions not updated for 30 days. "Cancelled on" uses `updated_at`, because there is no `cancelled_at`.
- Dates: weekday + long date in the drawer, weekday + short date in the table (matching Orders' "7 Oct").
- Inside the cutoff, a contact link.
- Deviation: no "delivery included". Delivery is only free inside the free zone, so the price reads "€60 per delivery".
