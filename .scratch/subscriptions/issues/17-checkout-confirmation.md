# Checkout and confirmation explain what happens next

Status: resolved

## Parent

`.scratch/subscriptions/spec.md`

## What to build

Audit items B3, B4, B7, B9 and B12 in `10-ux-audit.md`. B6 is settled by `14-card-on-file.md` (cards only), so "charged to this card" stays.

## Acceptance criteria

- [x] **B3.** Confirmation page (`checkout/order_live.ex`): "Next delivery Friday 30 October, €60 charged 3 days before" and a **Manage subscription** link to `/account`. Guests see "Sign in with {email} to skip, pause or cancel."
- [x] **B4.** Under the checkout email field for subscription carts: "We'll set up an account with this email so you can skip, pause or cancel." The newsletter "15% off your first order" is hidden for subscription carts.
- [x] **B7.** "A few days before" becomes "3 days before" (from `lead_days`), with the weekday date format.
- [x] **B9.** The cart line shows "€60 / delivery" and the interval at full contrast, with a "Change" link back to the product page.
- [x] **B12.** On mobile, a line above Pay: "Today €51 · then €60 every 2 weeks".
- [x] Strings translated (sv, fi). Tests for B3 (signed-in and guest) and B4.

## Blocked by

- `14-card-on-file.md`

## Comments

**Built (slice 17)**

- Confirmation: "Next delivery {weekday date}, {amount} charged 3 days before." The amount is today's line subtotal plus the fee. Signed in: **Manage subscription**. Guest: "Sign in with {email} to skip, pause or cancel."
- Checkout: an account note under the email field for subscription carts. The newsletter "15% off" offer is hidden for them.
- The consent line says "3 days before" (from `Subscription.lead_days/0`) and uses the weekday date.
- Cart line: "Subscription · Every 2 weeks · Change" at full contrast, and "per delivery" under the price.
- B12 needed no change: the Pay button already names today's amount ("Pay €51"), and the consent line right above it gives the recurring amount.
