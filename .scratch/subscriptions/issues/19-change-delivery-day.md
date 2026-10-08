# Let a customer change the delivery day

Status: resolved

## Parent

`.scratch/subscriptions/spec.md`

## What to build

Raised by David on 2026-10-08. Today the weekday is fixed by the first order. Changing it means cancelling and starting again.

Add a "Delivery day" choice to the drawer's Plan row, offering only the weekdays the subscription's fulfillment option delivers on (`available_days`). Choosing one moves `next_fulfillment_date` to the first date on that weekday that is outside the charge window (`lead_days + 1`), and the interval carries on from there. This mirrors `RescheduleForInterval`.

## Open questions

- Should a closed date (`enabled_dates` / date overrides) push the occurrence to the next open day, or skip it? This is the same question as for occurrences generally.
- Same cutoff as size/frequency changes?

## Blocked by

None.

## Comments

**Built (slice 19)**

- `Subscription` `:change` takes a `delivery_day` argument (`Fulfillment.Weekday`). `Validations.SubscriptionDeliveryDay` allows only the fulfillment option's `available_days` ("Choose one of the days we deliver on."). The cutoff is the same as for size and frequency.
- `Changes.Reschedule` (was `RescheduleForInterval`) handles both changes. A new interval counts from the `last_delivery_date` aggregate. A new day moves the date to the nearest matching weekday, up to 3 days either way, and then steps out of the charge window along the schedule. A skipped next delivery stays skipped on its new date.
- Answers to the open questions: closed dates were already handled, since `CreateOccurrence.first_open_day/2` moves an Occurrence to the next open day. The cutoff matches the other plan changes.
- Drawer: a "Delivery day" select in the Plan form, listing localized weekday names (`Format.weekday_name/2`). Save is enabled only when something differs, and the confirmation names the new first date.
- Tests: nearest-day moves both ways, day and interval changed together, an unavailable day refused, the skip carried; one account page test.
