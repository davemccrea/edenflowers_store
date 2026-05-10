# ADR 0001: Immutable orders via snapshot + per-action lockdown

Date: 2026-05-10
Status: Accepted

## Context

`Edenflowers.Store.Order` does two jobs:

1. The customer's evolving cart-during-checkout — mutable, browser-owned.
2. The placed order — should be immutable record of what was bought.

Issue #149 weighed splitting these into two resources. The conclusion (and a
subsequent reversal of an in-flight split PR, #157) was that for Eden Flowers'
current scale, the two-resource maintenance cost outweighs the marginal
cleanliness win. Future-features benefits (reorder, abandoned-cart,
amendments) are hypothetical until those features land.

This ADR records the chosen alternative: stay single-`Order`, but adopt the
Spree pattern of "complete = locked" — denormalise key data and gate every
post-place mutation at the policy layer, so the row is *effectively*
immutable on cart-flow fields after `state == :placed`.

## Decision

Three concrete moves:

### 1. Denormalise key data onto the row

Cart-flow data that depends on upstream rows (promotion percentage, tax rate,
fulfillment option pricing) must not be recomputed live for placed orders.
At each point that data resolves, capture the *value* onto the order, not a
pointer back to the upstream row.

Already in place before this ADR:

- `LineItem.unit_price`, `LineItem.tax_rate` — captured at add-to-cart from
  the variant. A later product price/tax edit doesn't change history.
- `Order.fulfillment_amount`, `Order.fulfillment_method` — captured at
  submit_delivery from the chosen fulfillment option.

Added by this ADR:

- `Order.fulfillment_tax_rate` — captured at submit_delivery /
  update_fulfillment_option from `fulfillment_option.tax_rate.percentage`.
  Closes the Finland VAT future-proofing gap: if Finland's VAT changes
  again (as it did recently), an admin edit to the existing tax_rate row
  will not retroactively alter what placed orders were quoted/charged.
- `Order.placed_line_total`, `placed_line_tax_amount`,
  `placed_discount_amount`, `placed_fulfillment_tax_amount`,
  `placed_tax_amount`, `placed_total` — captured at finalize_checkout
  from the cart's live aggregates and calculations. Concrete decimals
  on the placed row.
- `Order.placed_promotion_code` — captured at finalize_checkout from
  `order.promotion.code`. A later admin edit to the promotion's code
  must not change what this order's receipt displays. The `promotion_id`
  FK stays for reporting (which promotion was used).
- `LineItem.placed_line_total`, `placed_discount_amount`,
  `placed_line_tax_amount` — captured per-line-item at the parent's
  finalize_checkout. These were Ash calculations that depended on the
  live `order.promotion.discount_percentage`; concrete decimals after.

The capture is implemented by `Order.Changes.SnapshotTotals`, which runs in
`before_action` on `:finalize_checkout` while the order is still `:payment`,
loads the live aggregates/calcs, and writes them as concrete attributes.
The line-item snapshot writes via `LineItem.snapshot_totals` under the
system actor.

### 2. Per-action policy lockdown

The previous broad policy `policy action_type(:update) do; authorize_if
expr(state in @checkout_states); end` is replaced with explicit per-action
policies:

- All cart-flow actions (`submit_*`, `return_to_*`,
  `update_fulfillment_option`, `add_card`, `remove_card`,
  `add_promotion_*`, `clear_promotion`, `set_gift`,
  `add_payment_intent_id`, `restart_checkout`) require
  `state in @checkout_states`. Once placed, no cart-flow action runs,
  even via the owner.
- `:finalize_checkout` requires `state == :payment`.
- `:mark_payment_failed` requires `state in @checkout_states`. A failed
  payment is meaningful only mid-checkout; post-place refunds are a
  different concept.
- `:update_locale` is allowed always (presentational, doesn't violate
  the snapshot).

LineItem mirrors:

- `:create` requires `order.state != :placed`.
- `:read` allowed for cart-flow line items (public-by-id) and for
  placed-order line items by their owner.
- `:update` / `:destroy` requires `order.state != :placed`. Even the
  owner cannot edit or remove a placed order's line items.
- A `:system`-actor bypass lets `SnapshotTotals` write `placed_*` fields.

### 3. Read sites use snapshot fields, not aggregates/calcs

The order confirmation email (and any future placed-order render path)
reads `placed_*` fields directly. Cart-flow code (CheckoutLive, cart
drawer) continues to use the live aggregates/calculations on the same
field names — those names are unchanged. The snapshot fields exist
alongside the live ones, with disjoint usage.

## Why this and not the split

See issue #149 for the full analysis. Summary:

- **Cost.** A two-resource split is a 5–10x effort multiplier (new
  resources, conversion logic, line-item rework, hook/plug rename,
  AshPhoenix forms re-pointed, prod data migration). Lockdown is a
  ~200-line change with no migration of existing data.
- **Functional parity for current needs.** Both designs produce the
  same observable behaviour for placed orders: snapshot is immutable,
  upstream edits don't propagate. Spree, Solidus, Sylius all run at much
  larger scale on the single-Order pattern.
- **Migration path preserved.** If a future trigger fires (reorder,
  abandoned-cart, admin amendments per #136), the split becomes
  attractive — the snapshot work done here is *exactly* what the split's
  conversion change would have done, so half the effort is already
  banked.

## How refunds, returns, fulfillment work after this ADR

Following Spree's pattern, post-place lifecycle goes through *separate
models*, not Order edits:

- **Payment status** lives on Order as a separate state field
  (`payment_status`). Today: `:pending`, `:paid`, `:failed`, `:refunded`.
  The `:refunded` transition will be admin-only when refunds become real.
- **Fulfillment status** lives on Order as `fulfillment_status`
  (`:pending`, `:fulfilled`). Admin-only `mark_fulfilled` action.
- **Refunds** (when implemented) will be a new `Edenflowers.Store.Refund`
  resource with its own `amount`, `reason`, `created_at`. Belongs to
  Order. Order itself is never edited.
- **Returns** (when implemented) will be a new
  `Edenflowers.Store.ReturnAuthorization` (and `Return`, `Reimbursement`
  if needed) resource. Order itself is never edited.

The placed Order row is the snapshot; everything that *happens to* the
order after place is a sibling row.

## What this PR contains

- `Order.fulfillment_tax_rate` and `Order.placed_*` attributes.
- `LineItem.placed_*` attributes and `LineItem.snapshot_totals` action.
- `Order.Changes.SnapshotTotals` change.
- `Order.Changes.CalculateFulfillmentCost` updated to capture
  `fulfillment_tax_rate`.
- `Order.Changes.ClearDeliveryFields` and `Order.Changes.ResetCheckout`
  updated to clear `fulfillment_tax_rate`.
- Per-action policies on Order, tightened policies on LineItem.
- Migration adding the new columns (all nullable; cart rows have them
  NULL, placed rows have them populated).
- Email template reads `placed_*` fields.
- `SendOrderConfirmationEmail` worker simplified — no aggregate/calc
  loads needed.

## Future work

- When the first placed-order admin amendment lands, introduce a
  dedicated `Refund` resource rather than mutating Order.
- When promotional history needs to survive code edits at the *report*
  level (not just the receipt level), the promotion model itself should
  evolve to support versioning or copy-on-write.
- Revisit issue #149's split if any of its triggers fire.
