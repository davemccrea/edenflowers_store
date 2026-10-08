# Product page: respect the cart and explain the subscription

Status: resolved

## Parent

`.scratch/subscriptions/spec.md`

## What to build

Audit items B1, B2, B8, B10, B11, B13 and B14 in `10-ux-audit.md` (`store/product_live.ex`).

## Acceptance criteria

- [x] **B1.** The cart drawer opens only when the add succeeds; a refused add shows its error on the page. When the cart holds other products, warn before the click.
- [x] **B2.** The picker starts from the matching cart line. "In your cart" when nothing differs, otherwise say what will change.
- [x] **B8.** The replacement note counts the lines and amount it replaces ("Replaces 3 bouquets (€180) in your cart").
- [x] **B10.** Size names are translated via `Admin.Components.variant_size_label/1`, here and in `components/cart/line_items.ex`.
- [x] **B11.** "Also as a subscription" is replaced by a 2–3 line explainer shown when Subscription is selected. Subscription is the default in the subscriptions category.
- [x] **B13.** A signed-in customer with an active subscription is told so before starting another, with a link to `/account`.
- [x] **B14.** `text-[0.6875rem]` replaced with an on-scale size.
- [x] Strings translated (sv, fi). Tests for B1, B2, B8, B13.

## Blocked by

None.

## Comments

**Built (slice 16)**

- The cart drawer opens only after a successful add: the server pushes `js-exec`, and a new `phx:js-exec` listener in `app.js` runs the drawer's `phx-show`.
- When a subscription can't join the cart, the page warns ahead of the click ("checked out on its own…") and the button becomes **View cart**.
- The picker starts from the matching cart line (variant, buy-once or subscription, interval). An identical selection says "This is in your cart." with **View cart**. Otherwise it says "Changes your cart from Medium, every 2 weeks to Large, every week." or "Replaces the 3 bouquets (€180) in your cart."
- Size names use `variant_size_label/1` on the product page (labels and image alt) and in the cart line items.
- "Also as a subscription" removed. The subscription explainer (charged 3 days before; delivered, never collected; skip/pause/cancel) shows when Subscription is selected. Subscription is the default for every subscribable product, rather than keying on a category slug.
- A signed-in customer with a live subscription is told so, with a link to `/account`.
- `text-[0.6875rem]` → `text-xs`.
