# Subscriber Discount

Status: needs-triage

## Problem

A Subscription currently costs the same as buying the same product once each time. A customer can get the same result by reordering, so convenience is the only reason to subscribe. Subscriptions are worth more to the shop than one-off orders: demand is predictable, so stems can be bought to match with less waste; florist's choice lets Jennie use what's in season; and recurring income adds up. The discount spends part of that value to get customers to sign up, and gives the most to the most frequent deliveries, which are worth the most.

## Proposed term

**Subscriber Discount**: the percentage taken off the bouquet on every order a Subscription makes, the first one included. It is set by how often the Subscription delivers: 20% weekly, 15% fortnightly, 10% every four weeks.
_Avoid_: subscription discount, member price, loyalty discount

Add to `CONTEXT.md` under Subscriptions when this is picked up.

## Decisions

1. **The rates are code constants next to `@intervals` on `Subscription`**: `%{1 => 0.20, 2 => 0.15, 4 => 0.10}`. Jennie doesn't edit prices herself, and changing a rate is a deploy, like the intervals.
   Rejected: a setting or admin editor. Add one only when the rates start changing often.

2. **The rate is snapshotted on the line item** (`subscriber_discount_rate`, nil for a one-off), so a placed order's price never changes when the constants do.
   - Cart: set from the line's `interval_weeks` when the line is added or switched (`KeepSubscriptionAlone` replace path included).
   - Occurrence: set from the Subscription's current `interval_weeks` in `:create_occurrence`. Occurrence lines have no `interval_weeks` themselves, so the rate can't be derived from the line.
   - A card that goes with the first order is not discounted. Only the bouquet line carries the rate.

3. **It's priced through the line item's existing `discount`/`total` calculations.** `discount` becomes the promotion rate when a promotion applies, otherwise `subscriber_discount_rate`, otherwise 0. VAT (`Calculations.Vat` reads line `total`), the order total, Stripe amounts and the Balance all follow without further changes.

4. **The delivery fee is not discounted**, the same as with promotions.

5. **No stacking with promotion codes.** A code can't be applied to a subscription cart ("Subscriptions are already discounted"), and `promotion_applied?` is false on a subscription cart, so a code applied before switching to a subscription stops counting.
   - This removes the "The discount applies to your first delivery." copy from checkout and the setup email, and the `first_order_discounted?` calculation.
   - Note that the 15% newsletter code is worth more than the monthly 10%. A monthly subscriber who has the code loses 5% on the first order and saves 10% on every one after that.

6. **Changing frequency changes the rate from the next Occurrence**, the same as other `:change` edits. The account page's frequency picker shows each option's rate so the customer sees what they'd gain or lose.

7. **Existing Subscriptions get the discount from their next Occurrence.** This happens without a backfill because Occurrences snapshot the rate when they're created. Orders already placed keep their price.

8. **Where it shows:**
   - Product page: each frequency option is labelled with its saving ("Weekly · save 20%"), and the price shows the discounted amount, with the full price struck through.
   - Checkout: a discount row, "Subscriber discount (20%)", in place of the promo code row.
   - Receipt and admin order detail: the existing discount row, labelled "Subscriber discount (20%)" when no promotion applies. Gate the row on the discount being positive, not on `promotion_applied?`.
   - Account subscription card: the price per delivery after the discount.
   - Setup email: "Every delivery is 20% off." in place of the first-delivery line.

9. **Jennie's edits to an Occurrence keep the rate on its bouquet line.** Lines she adds herself are not discounted. Check that `ReplaceLineItems` carries the rate over and doesn't recreate the line without it.

## Accepted risk

A customer can subscribe, take the discount on the first delivery, and cancel. Each time costs at most the rate times one bouquet. This was accepted on purpose so that the saving shows at checkout. If it gets abused, options in order of preference:
1. Discount only from the second delivery ("20% off every delivery after your first").
2. Allow one discounted first order per customer email or saved card.
3. Raise the rate gradually over the first few deliveries.

Minimum terms and clawbacks were ruled out because they undercut "cancel anytime", and Finnish consumer law limits them.

## Out of scope

- Gift subscriptions with a fixed number of deliveries.
- Free or reduced delivery for subscribers.
- Perks such as priority on peak days or a vase with the first delivery.
