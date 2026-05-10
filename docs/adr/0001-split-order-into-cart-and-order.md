# ADR 0001: Split `Order` into `Cart` + `Order`

Date: 2026-05-10
Status: Accepted (in flight)
Triggers: Issue #149 (decision recorded for the future); decision to act now made
in the conversation that produced this PR.

## Context

`Edenflowers.Store.Order` did two jobs:

1. The customer's evolving cart-during-checkout — mutable, browser-owned, with
   form-progress state, geocoded address, fulfillment quote, payment intent.
2. The placed order — immutable record of what was bought, with
   `payment_status`, `fulfillment_status`, `ordered_at`, line items snapshot.

The state machine made the duality visible: `:contact_details → :gift_options
→ :delivery → :payment → :placed`. The first four are form-progress
sub-states; `:placed` is a different kind of thing — a lifecycle transition
out of "in checkout" and into "this happened."

Issue #149 weighed the trade-offs and recorded the analysis for a future
trigger. The decision in this conversation was to act now and accept the
multi-PR effort.

## Decision

Split into two resources:

- **`Edenflowers.Store.Cart`** — mutable, browser-owned. Owns the form-progress
  state machine (`:contact_details → :gift_options → :delivery → :payment →
  :converted`), all checkout fields (customer, gift, delivery, fulfillment
  quote, payment intent), and all `submit_*` / `return_to_*` / `add_card` /
  `update_fulfillment_option` / `add_promotion_*` actions.
- **`Edenflowers.Store.Order`** — immutable, post-conversion. Snapshot of what
  was bought: customer fields, addresses, totals, line items, all frozen at
  place-time. The only mutable surface is the post-place lifecycle —
  `payment_status`, `fulfillment_status` — driven by `mark_paid`,
  `mark_failed`, `mark_fulfilled`.

Line items split too:

- **`Edenflowers.Store.CartLineItem`** — mutable, belongs to a `Cart`,
  add/remove/increment/decrement actions.
- **`Edenflowers.Store.OrderLineItem`** — immutable, belongs to an `Order`,
  no mutating actions; values are frozen at conversion.

Conversion happens in one place. The Stripe webhook's
`payment_intent.succeeded` handler calls `Cart.convert/2`, which:

1. Creates an `Order` from a snapshot of the cart's fields and aggregates.
2. Creates `OrderLineItem` rows from the cart's `CartLineItem` rows.
3. Transitions the cart to `:converted` (kept for audit/refund linkage).
4. Returns the new `Order`.

The Stripe `metadata` carries `cart_id` (was `order_id`). The customer's
session points at the `Order` after the redirect from
`CheckoutCompleteController`.

## Consequences

### What goes well

- **Single responsibility per resource.** Cart policies = "is this in
  checkout?" Order policies = "is this the owner?" No more
  `state in @checkout_states` lists.
- **Order is truly immutable on cart-flow fields.** The actions don't exist.
- **Conversion is named.** `Cart.convert/2` creates a new entity, not a
  state transition on the existing row — a more honest model.
- **Cart's state machine no longer has `:placed` mixed in with form-progress
  states.** The transitions diagram makes intuitive sense.
- **Unlocks future features without retrofitting**: cart abandonment recovery,
  saved carts, draft orders, "buy again" / reorder, gift-card redemption
  history, partial refunds without disturbing the cart they came from.

### What goes badly

- **Two-resource consistency adds a category of subtle bug.** Cart and Order
  can drift after conversion (this is *correct* — that's why we want
  snapshots — but it's behaviour that didn't exist before).
- **Mental overhead.** "Give me the order, I'll show you everything about it"
  stops being true. During the flow you reach for the Cart, after place-time
  you reach for the Order.
- **Migration is non-trivial.** See PR scoping below.

## PR scoping

This is being executed as a multi-PR effort, in line with the recommended
sequence in issue #149:

### PR 1 (this PR) — tracer bullet

- New `Cart`, `CartLineItem`, `Cart.Changes.*`, `Cart.Validations.*`,
  `Cart.Changes.ConvertToOrder`.
- Slimmed `Order`, new `OrderLineItem` (immutable snapshot).
- Migration creating `carts`, `cart_line_items`, `order_line_items`; reshaping
  `orders` (drop cart-flow columns).
- `Edenflowers.Store` domain wiring.
- Stripe webhook calls `Cart.convert/2`.
- Hook/plug renames: `InitStore` creates `Cart`, `PutCart` hook replaces
  `PutOrder` for the checkout session, `PutOrder` repositioned for `OrderLive`.
- `CheckoutLive` re-pointed to `Cart`.
- `OrderLive`, `AccountLive`, `LineItemsComponent`, `Layouts.app`,
  `CheckoutCompleteController`, `SendOrderConfirmationEmail`, `Email`
  templates updated.
- Tests: enough to compile against new module names.

### PR 2 — production data migration (behind a flag)

- Backfill `carts` from existing `orders` rows in checkout sub-states.
- Snapshot existing `:placed` orders into the new shape (most fields stay,
  drop the cart-flow ones; line_items split between `cart_line_items` and
  `order_line_items` based on parent state).
- Drop legacy `orders` cart-flow columns and the `state` column entirely.
- Drop legacy `line_items` table.

### PR 3 — full test coverage rewrite

- Cart-flow tests on `cart_test.exs`, `cart_line_item_test.exs`.
- Order-lifecycle tests on the new slim `order_test.exs`.
- Conversion tests covering cart → order snapshotting (all ~25 fields,
  promotion amount-not-pointer, geocoded distance-not-option-id, etc.).
- LiveView tests adjusted for the new assigns shape.

### PR 4+ — admin queries, observability, follow-ups

- AshAdmin views revisited for the two-resource shape.
- Worker arguments and uniqueness keys reviewed for correctness on the new
  shape.

## Open invariants the conversion code must preserve

These are the spots issue #149 explicitly flagged as easy to get wrong; they
are encoded in `Cart.Changes.ConvertToOrder`:

- Snapshot the discount **amount**, not the **promotion**: a later promotion
  edit must not change the placed order's discount.
- Snapshot the geocoded **distance** and **fulfillment_amount**, not the
  `fulfillment_option_id`: a later option edit must not change the placed
  order's delivery cost.
- Snapshot `customer_name`, `customer_email`, `recipient_*`: account edits
  must not back-edit placed orders.
- Snapshot `tax_amount`, `total`: numbers on the receipt must match what was
  charged.
