# Subscriptions

Status: ready-for-agent

## Context
Customers should be able to get flowers on a schedule without checking out each time. Decided:
- **Payment**: card saved at first checkout, charged off-session before each delivery.
- **Product**: florist's choice at a fixed price — Jennie picks the flowers each time, so it never goes stale against a seasonal catalogue.
- **Setup**: by the customer at checkout; managed (skip / pause / cancel) from the account page.

Core idea: a **Subscription** is a template + schedule. Before each delivery an Oban job copies it into an ordinary placed **Online Order** and charges the saved card. Everything downstream (fulfilment views, emails, Payments, refunds, VAT, sales) already works on orders and needs no changes.

## Domain (add to CONTEXT.md, plus ADR 0003)
- **Subscription**: a customer's standing request for a florist's-choice bouquet every N weeks. Not an order; it *creates* orders.
- **Occurrence**: one order created from a subscription.
- ADR: "Subscriptions create ordinary orders" — why we don't use Stripe Billing (schedule lives here, Stripe only stores the card; one source of truth for dates; reuses Payment rows/ADR 0002).

## Data model
New `Edenflowers.Orders.Subscription` (Ash resource, AshStateMachine, AshPaperTrail like Order):
- `state`: `:pending` (checkout not paid yet) → `:active` ↔ `:paused` → `:cancelled`; `:payment_failed` (card declined/needs auth)
- `product_variant_id` — the florist's-choice variant (size)
- `interval_weeks` (1, 2, 4), `next_fulfillment_date`, `skipped_dates {:array, :date}`
- snapshot of delivery fields copied from the first order: recipient name+phone, `delivery_address`, `delivery_instructions`, `fulfillment_option_id`, `card_message`, `locale`. No fee or geocoded fields (see fee notes below).
- Customer name/email are **read from the user** at occurrence time, not snapshotted — the account page can now change them (`f8d1379`), and receipts should follow.
- `stripe_customer_id`, `stripe_payment_method_id`
- `belongs_to :user` (required — needs an account to manage it), `has_many :orders`

Order gets `belongs_to :subscription` (nullable).

Catalog: one Product ("Seasonal bouquet subscription") in its own category with S/M/L variants. Flag `subscribable` on Product (or just the category) so checkout knows to offer the frequency choice and the storefront hides it from normal browsing if wanted.

## Checkout changes (`lib/edenflowers_web/features/checkout/checkout_live.ex`, `lib/edenflowers/orders/order.ex`)
- If the cart contains a subscribable variant: show frequency select; cart restricted to that single line item (keeps fee/VAT per occurrence simple). Require login/email → user via existing `UpsertUserAndAssignToOrder`.
- `Payments` (`lib/edenflowers/payments.ex:37`) / `StripeApi.create_payment_intent`: for subscription carts pass `customer:` (create Stripe Customer) and `setup_future_usage: "off_session"`. Add `create_customer/1` and `charge_off_session/3` to the `StripeApi` behaviour (`lib/edenflowers/external/stripe_api.ex`) so the test mock covers them.
- `finalize_checkout` (order.ex:466): new change `Changes.ActivateSubscription` — creates the Subscription from the order snapshot, stores customer + payment method from the PaymentIntent, sets `next_fulfillment_date = fulfillment_date + interval`.

## Creating occurrences (Oban, same pattern as existing `oban do triggers` in order.ex:146)
Trigger `:create_occurrence` on Subscription: `state == :active and next_fulfillment_date <= today + lead_days`.
Action `create_occurrence`:
1. If date is in `skipped_dates` → just advance `next_fulfillment_date`.
2. Create Order (`origin: :subscription` — new Origin value, `subscription_id`), line item via the existing `LineItem` `:add_to_cart` create (`PopulateFromVariant` gives current price, tax rate, `free_delivery`), run `PriceFulfillment` / `SnapshotFulfillmentMethod` / `SnapshotVatBreakdown` (reuse from `lib/edenflowers/orders/changes/`).
3. `charge_off_session` with idempotency key `"sub-#{id}-#{date}"`.
   - success → place order + `RecordPayment` method `:stripe` (same as finalize_checkout), confirmation email trigger fires as today.
   - `authentication_required` / declined → subscription `:payment_failed`, order placed unpaid with a **Payment Link** (`Changes.OpenPaymentLink`) emailed to the customer, Jennie sees it flagged unpaid (ADR 0001 already covers this).
4. Advance `next_fulfillment_date`.

Fee notes (after `d601b0b` "Derive the delivery fee from the cart"):
- `fulfillment_fee` is now a **calculation** (`quoted_fulfillment_fee`, zeroed when `in_free_delivery_zone` and the cart has a `free_delivery?` line item, unless overridden). Never copy a fee onto the subscription; the occurrence gets `quoted_fulfillment_fee` + `in_free_delivery_zone` from `PriceFulfillment`.
- Build the occurrence's line item through the normal line-item create so `PopulateFromVariant` snapshots `free_delivery` from the product. The subscription product is always `free_delivery` (see Decisions), so occurrences in the free zone cost nothing to deliver.
- `PriceFulfillment.needs_geocoding?` is always true on create, so every occurrence calls HERE. Fine at weekly volume, but a geocoding outage would fail the occurrence: the Oban job must retry, not cancel. If that bites, let create reuse a passed-in `distance` (custom orders never pass one, so `place_custom` is unaffected).

Webhook reconciliation already handles PaymentIntents by metadata, so pass the order id in metadata as today.

`lead_days` (e.g. 3): gives Jennie notice to buy flowers. Fulfillment-date validations (closed days, `FulfillmentDateNotPast`) — if the date is a closed day, roll forward to next open day.

## Customer management (`lib/edenflowers_web/features/account/account_live.ex`)
List subscriptions with next date; actions: skip next, pause/resume, change size/frequency, cancel, update card (Stripe SetupIntent via Payment Element). Address change: simplest is "cancel and start a new one" initially.

## Admin
- Order list/detail: badge "Subscription" on occurrences (Origin).
- Subscriptions list page under `features/admin/` (Cinder table like existing lists): state, customer, next date; Jennie can skip/cancel/pause.

## Emails
- "Your subscription is set up" (on activate), "Upcoming delivery in N days — skip?" (optional, nice), "Payment failed — pay here" (Payment Link). Existing confirmation/delivered emails cover occurrences.

## Suggested slicing (tracer bullets)
1. Subscription resource + checkout opt-in + saved card + ActivateSubscription (no occurrences yet; visible in admin).
2. Occurrence job with off-session charge, happy path.
3. Failed charge → payment_failed + Payment Link.
4. Account page: skip / pause / cancel.
5. Change size/frequency, update card, upcoming-delivery email.

## Decisions
- Delivery only: checkout rejects a pickup option for a subscription cart; the subscription never offers one.
- Free delivery within the free zone, always: the subscription product is `free_delivery`, and a Product validation (`subscribable` implies `free_delivery`) stops it being unticked. Uses the existing free-zone rule (option's `free_dist_km`, 5 km in seeds, by road from `HereAPI` `@origin`); no new fee code.
- Current prices for each occurrence (item and delivery fee). Prices change rarely; the confirmation email already shows what was charged.
- Skip / pause / cancel allowed until 24h before the occurrence is created; `lead_days` must be > 1 so this lands before the charge.
- Closed day → move to the next open day.

## Open questions
- Interaction with the parked **Delivery Windows** spec (`.scratch/delivery-windows/spec.md`): if it ships first, the subscription snapshots the window id and the surcharge folds into the fee as that spec describes; nothing here blocks it.

## Verification
- Unit tests on Subscription actions with Stripe mock (existing `StripeApi` behaviour mock): activate from finalize_checkout, occurrence success, `authentication_required` path, skip, idempotent re-run of the Oban job (no double order/charge).
- `Oban.Testing` `perform_job` for the trigger.
- Manual: Stripe test card `4000002500003155` (requires auth off-session) and `4242…` in dev with `stripe listen` webhooks; set `next_fulfillment_date` to today and run the trigger from Oban Web.
- `source .env && mix test`.
