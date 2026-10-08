# Cards only for subscriptions, and show the card on file

Status: resolved

## Parent

`.scratch/subscriptions/spec.md`

## What to build

Audit items A4, A19 and the Klarna part of B6 in `10-ux-audit.md`.

Decisions:
- Subscription PaymentIntents and SetupIntents use `payment_method_types: ["card"]` instead of `automatic_payment_methods`. One-off orders keep automatic payment methods.
- Store the card's brand, last 4 digits and expiry on the Subscription when a card is saved.

## Acceptance criteria

- [x] `create_payment_intent_saving_card` and `create_setup_intent` in `external/stripe_api.ex` offer cards only. `create_payment_intent` is unchanged.
- [x] Subscription gets `card_brand`, `card_last4`, `card_exp_month`, `card_exp_year` (migration). Set at checkout activation and on `:replace_card`, from the Stripe payment method.
- [x] Account row shows "Visa •••• 4242, exp 08/27" next to "Update card"; the card page names the current card.
- [x] The card page's "temporarily unavailable" fallback names the current card and a contact route.
- [x] Existing subscriptions without stored card details show nothing rather than crashing.
- [x] Strings translated (sv, fi). Tests with the Stripe mock.

## Blocked by

None.

## Comments

**Built (slice 14)**

- `create_payment_intent_saving_card` and `create_setup_intent` use `payment_method_types: ["card"]`. One-off orders keep automatic payment methods.
- Subscription `card_brand`, `card_last4`, `card_exp_month`, `card_exp_year` (migration `20261008200921`), set by `Changes.SnapshotCard` on `:activate` and `:replace_card` through the new `StripeAPI.retrieve_payment_method/1`. A failed lookup logs and leaves the fields blank, so it never blocks activation or a card change.
- Backfill: `Edenflowers.Release.backfill_subscription_cards/0` (system-only `:snapshot_card` action). In dev it found no card for any existing subscription: the seeded ids are fake, and the one real subscription paid with Stripe **Link** (`type: "link"`, no card details). The seeds now set Visa 4242.
- Shown as "Visa •••• 4242, expires 08/27" (`Fields.card_label/1`) in the drawer and on the card page. Falls back to "Saved card". The card page's unavailable state says the current card stays in place and links to contact.
- Tests: the Stripe mock's `retrieve_payment_method` is stubbed by default in `DataCase`/`ConnCase` (`stub_card_lookup/0`).
