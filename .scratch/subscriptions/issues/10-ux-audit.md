# Fixes from the subscription UX audit

Status: resolved

## Parent

`.scratch/subscriptions/spec.md`

## Context

UX audit (2026-10-08) of the customer-facing subscription UI, run in a real browser at 1440 and 390 px wide, in en, fi and sv-FI. Bar: looks right, but above all functional and self-explanatory, especially `/account`. The visual system matches DESIGN.md throughout; the gaps are in what the screens explain and in a few behaviours.

Testing notes for the next session:
- The dev server is on **:4001**; port 4000 is an unrelated app.
- Sign in at `/sign-in`; OTP codes appear at `/dev/mailbox`. `/sign-out` asks you to confirm.
- Seeded customers: helena.nyman (active, next delivery skipped, gift to Ingrid), otto.makinen (paused), sara.holm (payment failed), jonas.berg (cancelled), all `@example.fi`. mail@dmccrea.me has one cancelled and one active subscription; the active one came from a real checkout, so its Stripe card page loads.
- The seeded Stripe customer ids are fake, so their card pages show the "Payment is temporarily unavailable" fallback.
- `audit.nosub@example.fi` was created for the empty state.
- Not yet tested: the changes-closed (24h cutoff) state, since no seeded subscription is inside the window; and a completed payment / fresh guest confirmation page.

Line numbers refer to the working tree on 2026-10-08 (uncommitted changes to `account_live.ex` and others), so re-check them.

## Decisions needed before building

- **Payment-failed recovery** (A1): should paying the held delivery's link also save that card for future deliveries, or should the page send the customer to "Update card"?
- **Unskip** (A6): add an `:unskip` action? Allow more than one skipped date?
- **Card on file** (A4): store brand, last 4 digits and expiry when a card is saved (needs fields on Subscription + Stripe payment-method lookup)?
- **Klarna** (B6, A15): limit subscription PaymentIntents and SetupIntents to `payment_method_types: ["card"]`, or keep Klarna and change the copy to "payment method"?
- **Product name**: "Weekly bouquet" sold every 2 or 4 weeks reads as a contradiction. Rename it (e.g. "Florist's choice bouquet") and seed translations.

## A. Account page (`lib/edenflowers_web/features/account/account_live.ex`)

### P0

- [ ] **A1. Payment failed: the copy doesn't match the behaviour, and the state isn't urgent.**
  - Status `"On hold until the last delivery is paid"` (`:575`) is grey 14px text with a small inline "Pay now". "Cancel subscription" is the most prominent control.
  - It's also wrong both ways. Paying the link reactivates the subscription (`changes/reactivate_subscription.ex`) but keeps the declined card, so the next charge will probably fail again. Saving a new card also reactivates it (`subscription.ex` `:replace_card`) while the delivery stays unpaid. And the unpaid delivery is the upcoming one, not the "last".
  - Fix: at the top of the row, in full-contrast text: "We couldn't charge your card for Tuesday 13 October (€60)." Primary button **Pay €60 now**, then "Update your card so future deliveries go through". Move Cancel to the end.
  - The `/pay/:token` page should say this delivery belongs to a subscription and that paying restarts it. See the decision above about saving the card.

### P1

- [ ] **A2. "Next delivery" ignores a delivery that's already booked.**
  - `subscription_status/2` (`:563`) shows `next_fulfillment_date`, the next delivery not yet created.
  - mail@dmccrea.me's active subscription says "Next delivery 06/11/2026" while its first delivery (order #1457) arrives on 9 Oct.
  - The skip confirmation (`:144`) has the same problem.
  - Fix: show the earliest upcoming placed order for the subscription when there is one.
- [ ] **A3. No charge timing or price unit.**
  - "Medium · Every 4 weeks · €60" (`:529–534`).
  - Fix: "€60 per delivery, delivery included. Next delivery Friday 9 October, charged on Tuesday 6 October" (lead days = 3).
- [ ] **A4. The card on file is never shown**, here or on the card page.
  - Fix: show "Visa •••• 4242, exp 08/27" next to "Update card" (see decision).
- [ ] **A5. Recipient and address are not shown.**
  - A gift subscription (Helena → Ingrid) looks like a self-subscription.
  - Fix: "To Ingrid Nyman, Gerbyntie 16, Vaasa". Add "To change the address, contact us" (the spec says changing address means cancelling and starting again).
- [ ] **A6. Skip can't be undone, and only the next delivery can be skipped.**
  - Fix: add a "Deliver on 14 October after all" button (see decision) and the hint "Away for longer? Pause instead."
- [ ] **A7. Pause doesn't explain itself.**
  - The status is just "Paused" (`:574`).
  - Fix: "Paused. No deliveries or charges." Add "Resume now and your next delivery is Monday 26 October", computed with the `StepToScheduledDate` logic.
- [ ] **A8. The cancel confirmation is a native `confirm()`** (`:173`). The button that keeps the subscription is labelled "Cancel", and there's no mention of pausing.
  - Fix: an in-app dialog, "Stop your subscription? No more deliveries or charges. Want a break instead? Pause it." Buttons "Stop subscription" and "Keep it". Focus moves into the dialog and back on close.
- [ ] **A9. The cancelled subscription is listed above the active one, and they look identical.**
  - The `:mine` read sorts by `inserted_at: :asc` (`subscription.ex:95`).
  - Fix: active, paused and payment-failed first, cancelled last, with "Cancelled on 8 October". Hide cancelled rows after about 30 days.

### P2

- [ ] **A10. Hierarchy.** Subscriptions sits below the name/email form and starts 614px down an 844px mobile screen. "Save changes" is the strongest element in the row.
  - Fix: move Subscriptions above "Your details". Lead each row with the status sentence at body size. Put size and frequency behind a **Change** button.
- [ ] **A11. Touch targets are 24px tall** (Skip, Pause, Cancel, Update card text buttons). Raise them to at least 44px.
- [ ] **A12. Cancelled is a dead end.** Add a "Start a new subscription" link to the product page.
- [ ] **A13. "Save changes" with nothing changed** still says "Subscription updated" (`:455`), and never says which delivery the change applies from.
  - Fix: disable Save until something changes. Confirm with "From 6 November: Small, every 4 weeks, €45 per delivery." Show the price per size option.
- [ ] **A14. Numeric dates** ("06/11/2026") while Orders uses "9 Oct". Use weekday + long date for all subscription dates (`:564–568`, `:128`, `:144`).
- [ ] **A15. Focus is lost after Pause or Resume** (the button is replaced, so focus drops to `<body>`). Give it a stable id per subscription, or `JS.focus` the status line.
- [ ] **A16. Inside the 24h cutoff every action disappears** (`:127–132`). Add "Need to change this one? Contact us."
- [ ] **A17. No empty state.** The section is hidden when there are no subscriptions (`:104`), while Orders and Courses have empty states with links. Add a one-line prompt linking to the subscription product.
- [ ] **A18. Orders don't mark subscription deliveries.** Add a "Subscription" label next to the status (the unpaid row already shows "Unpaid · Pay now").

### P3

- [ ] **A19. Card page** (`subscription_card_live.ex`): Klarna is offered under "Update your card" (see decision). The fallback should name the current card and a contact route.

## B. Purchase flow

### P1

- [ ] **B1. A refused add-to-cart is hidden behind the cart drawer** (`store/product_live.ex:235`). The submit always runs `JS.exec("phx-show", to: "#cart-drawer")`, so the "checked out on its own" error lands under the drawer.
  - Fix: warn before the click when the cart holds other products, and only open the drawer when the add succeeds.
- [ ] **B2. The product page ignores what's in the cart** (`product_live.ex:45`, `:226–238`). With a fortnightly subscription in the cart it reloads as "Buy once / Every week" with an active "Update cart".
  - Fix: start from the cart line. Show "In your cart" when nothing differs, otherwise say exactly what changes.
- [ ] **B3. The confirmation page** (`checkout/order_live.ex:91–98`) has no next date or amount, and no link to manage the subscription.
  - Add "Next delivery Friday 30 October, €60 charged 3 days before" and a **Manage subscription** link to `/account`. For guests: "Sign in with {email} to skip, pause or cancel."
- [ ] **B4. Checkout never says an account is created** (`checkout_live.ex:104–125`).
  - Under the email field: "We'll set up an account with this email so you can skip, pause or cancel."
  - Hide the newsletter "15% off your first order" for subscription carts.
- [ ] **B5. The FAQ is wrong** (`faq_live.ex:29`). It promises weekly/bi-weekly/monthly and 10% off all orders.
  - Rewrite: every 1, 2 or 4 weeks, free delivery within 5 km, charged 3 days before each delivery, skip, pause or cancel from your account. Update fi/sv.

### P2

- [ ] **B6. Klarna is offered but the copy says "charged to this card"** (`checkout_live.ex:541`). See decision.
- [ ] **B7. "A few days before" is vague, and "30/10/2026" doesn't match the weekday date above it** (`checkout_live.ex:536–541`). Say "3 days before" and use the weekday format.
- [ ] **B8. Silent bulk replacement.** Three one-off bouquets (€180) become one subscription with the note "Replaces the bouquet in your cart" (`product_live.ex:226`). Count the lines and show the amount.
- [ ] **B9. The cart doesn't make the recurrence obvious** (`components/cart/line_items.ex:57–61`).
  - Show "€60 / delivery" and the interval at full contrast.
  - Commit bdfe811 says customers can switch in the cart, but there is no control there. Add a "Change" link back to the product page, or drop the claim.
- [ ] **B10. Size names stay in English in fi and sv** (`product_live.ex:161`, `line_items.ex:55`). Reuse `AdminComponents.variant_size_label/1`.
- [ ] **B11. Product page explainer.** It defaults to "Buy once", and "Also as a subscription" duplicates the picker (`product_live.ex:121–132`).
  - Replace the duplicate with a 2–3 line explainer when Subscription is selected.
  - Consider Subscription as the default in the subscriptions category.

### P3

- [ ] **B12. On mobile, the total sits below the Pay button.** Add a one-line "Today €51 · then €60 every 2 weeks" above it.
- [ ] **B13. A signed-in customer with an active subscription isn't warned** before starting a second one.
- [ ] **B14. One off-scale font size**, `text-[0.6875rem]` at `product_live.ex:88` (from the design-system scan).

## Keep

- The consent sentence directly above Pay ("Pay €51, then €60 every 2 weeks from …, charged to this card").
- "The discount applies to your first delivery" and "The card comes with your first delivery".
- Pickup hidden for subscriptions, with a one-line reason.
- Real buttons and labelled selects, `role=group` labelled by the subscription name, a visible 2px focus outline, and a logical tab order.
- The card page copy: "Every delivery from now on is charged to the card you save here", plus the "doesn't pay it" warning.
- Server-side cutoff validation with plain error messages; pause and resume need no confirmation.

## Account page structure

Keep Subscriptions as its own section (don't merge it into Orders), move it up, and connect the two with A18 plus a "Past deliveries" link from the subscription.

## Comments

### Triage (2026-10-08)

Status → `needs-info`. Spot-checked against the working tree: A1 (`:575`), A2 (`:144`, `:564`), A8 (`:173`), A9 (`subscription.ex:95`), B1 (`product_live.ex:235`), B5 (`faq_live.ex:29`) and B6 (`stripe_api.ex` uses `automatic_payment_methods`, so Klarna is live) all hold. No `:unskip` exists.

Too big for one ticket: ~33 items and five open decisions. Once the decisions are in, split into these and close this one as the umbrella:

| # | Slice | Items | Blocked on |
|---|-------|-------|------------|
| 11 | Payment-failed recovery | A1, `/pay/:token` copy | Payment-failed decision |
| 12 | Account status tells the truth | A2, A3, A7, A9, A14, A16 | — |
| 13 | Account actions | A6, A8, A11, A13, A15 | Unskip decision (A6 only) |
| 14 | Card on file | A4, A19 | Card-on-file + Klarna decisions |
| 15 | Account layout and links | A5, A10, A12, A17, A18 | — |
| 16 | Product page | B1, B2, B8, B10, B11, B13, B14 | — |
| 17 | Checkout and confirmation | B3, B4, B6, B7, B12 | Klarna decision (B6 only) |
| 18 | FAQ and product name | B5, rename + translations | Product-name decision |

12, 15 and 16 can go `ready-for-agent` now. Suggested order: 11 → 12 → 16 → 17 → rest.

Recommended answers (to confirm):
- **Payment failed:** paying the held delivery's link should *not* silently save the card. Make the page's primary path "Update card", then pay; keeps one place where the card on file changes.
- **Unskip:** yes to `:unskip`; keep one skipped date ("Away longer? Pause.").
- **Card on file:** yes, store brand/last4/exp on `:replace_card` and at checkout.
- **Klarna:** cards only (`payment_method_types: ["card"]`) for subscription intents; check whether Klarna supports off-session charges for Finland before keeping it.
- **Product name:** rename; Jennie picks the name.

**Split (2026-10-08).** Decisions accepted as recommended above. Work continues in issues 11–18; this issue stays as the audit record.
