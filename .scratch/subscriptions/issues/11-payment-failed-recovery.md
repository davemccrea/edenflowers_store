# Make a failed payment urgent and recoverable

Status: resolved

## Parent

`.scratch/subscriptions/spec.md`

## What to build

Audit item A1 in `10-ux-audit.md`. A payment-failed subscription currently reads "On hold until the last delivery is paid" in grey 14px text, and the copy is wrong both ways: paying the link reactivates the subscription but keeps the declined card, and saving a new card reactivates it while the delivery stays unpaid.

Decision: paying the held delivery's link does **not** save the card. The card on file only changes through "Update card". The account row leads with updating the card, then paying.

## Acceptance criteria

- [x] The payment-failed row leads with a full-contrast sentence naming the unpaid delivery's date and amount: "We couldn't charge your card for Tuesday 13 October (€60)."
- [x] Primary action **Update card**, then **Pay €60 now** (the existing pay link). Cancel moves to the end of the row.
- [x] Copy explains that both are needed: the new card covers future deliveries, paying covers this one.
- [x] The amount and date come from the unpaid placed order for the subscription, not `next_fulfillment_date`.
- [x] `/pay/:token` for a subscription order says the delivery belongs to a subscription and that paying restarts it, and links to "Update card" for future deliveries.
- [x] Strings translated (sv, fi).
- [x] Tests for the row copy and the pay-page note.

## Blocked by

None.

## Comments

**Built (slice 11)**

- Account row (`account_live.ex`, `subscription_payment/1`): a held subscription leads with "We couldn't charge your card for {weekday date} ({amount})." and "Update your card to restart your subscription. A new card doesn't pay for this delivery, so pay for it separately." Buttons: **Update card** (primary), **Pay €X now**. If the payment link is gone, it says the subscription is on hold and offers only Update card.
- The same block stays on an *active* subscription that still has an open payment link ("Your delivery on … (€X) is still unpaid." + Pay). This covers the case where a new card restarts the subscription but the old delivery is still unpaid.
- A held row hides the size/frequency form and the separate Update card link, so Cancel comes last.
- `/pay/:token` for an Occurrence explains that paying restarts a held subscription but doesn't change the card, and links to the card page.
- Confirmed the pay link doesn't save the card: an Occurrence already has its off-session PaymentIntent, so `Payments.setup/2` retrieves it and doesn't create a card-saving one.
- 8 strings, fi/sv. Tests: 2 in `account_live_test.exs` (replacing the old pay-link test), 1 in `pay_live_test.exs`.
- Not checked in a browser: Playwright was busy in another session.

**Superseded layout (2026-10-08).** Issue 15's rework moved the subscription controls into a Manage drawer. The held state now shows "Payment failed" with **Pay €X now** · **Update card** in the Subscriptions table's Next delivery column, and the full explanation and buttons at the top of the drawer.
