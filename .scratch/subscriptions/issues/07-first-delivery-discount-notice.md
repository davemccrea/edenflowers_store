# Say a promotion only discounts the first delivery

Status: resolved

## Parent

`.scratch/subscriptions/spec.md`

## What to build

A promotion code applies only to a subscription's first order. Later deliveries (Occurrences) are separate orders that carry no promotion, so they are charged at full price. Nothing tells the customer this today. Checkout and the set-up email show the reduced first total, and the second delivery then costs more.

When a subscription cart has a promotion applied, show a short notice: "The discount applies to your first delivery." It appears in two places:

- the checkout summary, next to the discount line
- the subscription set-up email, when the first order had a discount

Behaviour stays as it is: Occurrences remain at full price.

## Acceptance criteria

- [ ] Checkout shows the notice only when the cart is a subscription and `promotion_applied?` is true. It never shows for a one-off cart, or when a code was entered but doesn't apply, e.g. below its minimum.
- [ ] The set-up email includes the notice only when the order that started the subscription had a promotion applied.
- [ ] The notice is translated into sv and fi.
- [ ] Tests cover the notice shown and hidden in checkout, and in the email.

## Blocked by

- `06-opt-in-on-product-page.md` (it changes how a cart becomes a subscription)

## Comments

**Built (slice 07)**

- Checkout: under the discount line, "The discount applies to your first delivery." shows when `promotion_applied?` and `subscription?` are both true (`data-testid="first-delivery-discount"`). It uses the promo component's existing hint style (`text-base-content/70 text-sm`).
- Set-up email: the new `Subscription.first_order_discounted?` calculation is `exists(orders, origin == :online and promotion_applied?)`. `Changes.SendSubscriptionSetupEmail` loads it, and the template adds the notice as its own paragraph after the details.
- 1 new string, translated into sv ("Rabatten gäller din första leverans.") and fi ("Alennus koskee ensimmäistä toimitustasi.").
- Tests: `checkout_delivery_live_test.exs` covers a subscription with a promotion (shown), a subscription below the code's minimum (hidden), and a one-off with a promotion (hidden). `subscription_test.exs` checks that a discounted first order gets the notice in the set-up email and that the existing undiscounted one doesn't.

**Decisions**

- The email reads `promotion_applied?` from the first order, the same rule checkout uses, so a code the cart had dropped below doesn't trigger the notice.
- Occurrences are unchanged and still carry no promotion.
