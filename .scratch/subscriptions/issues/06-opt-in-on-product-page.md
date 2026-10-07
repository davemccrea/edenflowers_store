# Opt in to a subscription on the product page

Status: resolved

## Parent

`.scratch/subscriptions/spec.md`

## What to build

Subscribing becomes an explicit choice the customer makes on the product page. Right now, putting a subscribable product in the cart turns checkout into a subscription and asks a required "How often" question.

The shop will most likely have a single subscribable product, "Weekly bouquet". It can be bought once like any other product, or subscribed to. Its product page offers:

```
(•) Buy once
( ) Subscribe — delivered regularly, skip or cancel any time
      How often: [Every week ▾]   (every 1, 2 or 4 weeks)
```

"Buy once" is selected by default. Only a line added with "Subscribe" makes the cart a subscription cart. Checkout no longer asks how often; it shows the choice made on the product page.

It should also be obvious which products can be subscribed to:
- The store marks them, e.g. a small "Also as a subscription" label on the product card and on the product page.
- The admin checkbox reads "Can be bought as a subscription" and has a short hint.
- The admin product list shows which products are subscribable.

## Acceptance criteria

- [ ] How often a line is to be delivered lives on the line item, set when it is added to the cart; empty means a one-off. The `subscription?` aggregate on Order and `ActivateSubscription` read it from there, and `Order.subscription_interval_weeks` and the checkout frequency question are removed. Adding a subscription line is refused for a product that isn't subscribable or for an interval other than 1, 2 or 4.
- [ ] A one-off Weekly bouquet behaves like any product: it can share the cart and be picked up. The "checked out on its own", delivery-only and single-quantity rules apply only to a subscription line.
- [ ] The same variant bought once and subscribed to are separate lines; the cart shows "Subscription · every 2 weeks" on a subscription line.
- [ ] The product page shows Buy once / Subscribe with a frequency select only for subscribable products, with Buy once preselected. The product card and product page carry the "Also as a subscription" label.
- [ ] Free delivery inside the free zone stays a product setting: a subscribable product must still be `free_delivery`, so a one-off Weekly bouquet, a subscription and every Occurrence all get it. (Decided with the user.)
- [ ] Occurrences (`CreateOccurrence`) still add their line as a one-off.
- [ ] Admin: clearer checkbox label and hint; subscribable products are marked in the product list.
- [ ] Seeds rename the subscription product to "Weekly bouquet".
- [ ] New strings translated into sv and fi.
- [ ] Tests are updated and cover a one-off Weekly bouquet (sharing the cart, pickup), the opt-in path through to activation, and the refusals.

## Blocked by

- `05-change-and-notify.md`

## Comments

**Built (slice 06)**

- `LineItem.interval_weeks` (nil = one-off) replaces the `LineItem.subscribable` snapshot. `:add_to_cart` accepts it and checks it with `attribute_in(Subscription.intervals())`. `PopulateFromVariant` refuses it ("This product can't be subscribed to") when the product isn't `subscribable`. `KeepSubscriptionAlone` and `increment_quantity` now key off `interval_weeks`.
- `Order.subscription?` is now `exists line_items where not is_nil(interval_weeks)`. `Order.subscription_interval_weeks` is removed, along with its place in `submit_delivery`'s accept list, in `ResetCheckout`, the checkout "How often" radio and the delivery step summary. `Validations.SubscriptionDelivery` only rejects pickup now. `ActivateSubscription` takes the variant and interval from the subscription line. `Payments` is unchanged; it still reads `subscription?`.
- Migration `move_subscription_interval_to_line_items` adds `line_items.interval_weeks` and drops `line_items.subscribable` and `orders.subscription_interval_weeks`.
- Product page: if the product is subscribable, "How to buy" offers Buy once (preselected) or Subscription. A "How often" choice (every week, 2 weeks or 4 weeks) and the line "Delivered regularly, skip or cancel any time" sit right beneath it. Both use the size selector's markup: `fieldset` + eyebrow `legend`, `label.size-option[data-active]` with an `sr-only` radio, and `size-option__label font-serif text-xl`. The "How often" fieldset stays in the layout and is `invisible` (and `aria-hidden`) until Subscription is chosen, so nothing shifts. "Also as a subscription" uses the free-delivery line's style (icon + `text-base-content/80`). The form got an id, which form recovery needs.
- Product card: "Also as a subscription" uses the existing "Free delivery" badge style, stacked under it at the top-left.
- Cart line shows "Subscription · Every 2 weeks" (reusing `Fields.interval_label/1`) and keeps hiding +/- for a subscription line.
- Admin: the checkbox reads "Can be bought as a subscription" and has a hint below it. The product list has a Subscription column (arrow-path icon, with sr-only text).
- Seeds: the product is renamed "Weekly bouquet".
- 7 new strings, translated into sv and fi.
- Tests: `subscription_test.exs` (subscription line refused against a one-off of the same size with that one-off untouched, non-subscribable product refused, interval 3 refused, a one-off Weekly bouquet sharing the cart and adding up, picked up and paid with no subscription started). The new `store/product_live_test.exs` covers Buy once preselected, the opt-in through to a line with `interval_weeks: 2`, no options on an ordinary product, and the store card label. `checkout_delivery_live_test.exs` checks the cart shows the interval with delivery only, and that a one-off can be picked up. `products_live_test.exs` checks the admin mark. `create_occurrence_test.exs` asserts the occurrence line is a one-off. Activation runs through `Payments.complete` in `subscription_test.exs`.

**Decisions and deviations**

- One-off vs subscription of the same variant: the `unique_product_variant` identity and its upsert are unchanged. A subscription line can't share a cart with any other non-card line, and `KeepSubscriptionAlone` refuses the add before the upsert runs, so the two are never merged. Adding the identity column would have needed `NULLS NOT DISTINCT` plus a partial index for custom items.
- Occurrences need no code change. `CreateOccurrence` passes no interval, so its line is a one-off. As a result an Occurrence is no longer `subscription?` (the old product snapshot made it true). That only affected which Stripe call a payment link on an Occurrence would have used.
- The product page radio says "Subscription" rather than "Subscribe", because the existing "Subscribe" msgid is the newsletter's ("Tilaa" in fi, which also means "order").
- The checkout delivery step summary no longer repeats the interval. The cart lines in the checkout sidebar show it.
- An invalid add on the product page still flashes the "checked out on its own" message. Only a tampered request can hit the other refusals.

**Open questions**

- The migration doesn't backfill. Any unpaid cart holding a subscription line when this deploys becomes a one-off cart. This doesn't matter if slices 01–05 haven't reached production.
- The seeded category is still "Subscriptions", although the product can now be bought once.
