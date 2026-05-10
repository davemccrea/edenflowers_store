# ADR 0001: Immutable orders via snapshot + per-action lockdown

Date: 2026-05-10
Status: Accepted

## Context

`Edenflowers.Store.Order` does two jobs on the same row:

1. The customer's evolving cart-during-checkout — mutable, browser-owned,
   driven through a state machine
   (`:contact_details → :gift_options → :delivery → :payment → :placed`).
2. The placed order — what was actually bought; should be an immutable
   record from the moment payment succeeds.

Today the boundary between these two jobs is implicit. After the state
transitions to `:placed`, nothing in the schema or in policy enforcement
prevents the row's cart-flow fields (customer name, addresses, gift
options, fulfillment quote, applied promotion) from being edited. And
even where fields *can't* easily change, derived numbers (line totals,
discounts, tax amounts) are still computed live from upstream rows
(promotions, tax rates, fulfillment options) — so an admin edit to a
promotion's percentage, or to a `tax_rate` row, retroactively rewrites
history on placed orders.

Two specific exposures motivate acting now:

- **Finland VAT.** Finland recently adjusted VAT percentages and is
  likely to do so again. Today, `Order.fulfillment_tax_amount` is
  computed live as
  `fulfillment_amount * fulfillment_option.tax_rate.percentage`. An
  admin edit to the existing `tax_rate` row would change the tax shown
  on every previously-placed order, including ones already paid and
  shipped at the old rate.
- **Promotion edits.** `Order.discount_amount` is an aggregate over
  `LineItem.discount_amount`, which is itself a calculation reading
  `order.promotion.discount_percentage`. The promotion's `code` is
  also read live via `order.promotion.code`. Either edit would rewrite
  the receipt for every order that used that promotion.

The narrow architectural question — "should there be one resource or
two?" — was weighed in issue #149 and the conclusion there was *not
yet*: the maintenance cost of a two-resource split outweighs the
marginal benefit at the current scale, and the strongest arguments for
splitting (reorder, abandoned-cart recovery, admin amendments per #136)
depend on features that aren't on the roadmap.

This ADR records the alternative chosen for the *immutability* problem,
which is real today regardless of how that question resolves: stay
single-`Order`, but make placed orders *effectively* immutable on
cart-flow concerns through denormalisation and per-action policies.

## Decision

Three concrete moves, summarised here and detailed below:

1. Denormalise upstream-dependent data onto Order and LineItem so a
   placed order's numbers don't depend on rows that can change.
2. Replace the broad cart-flow-only `:update` policy with explicit
   per-action policies that gate every mutating action on the
   appropriate state.
3. Read sites for placed orders consume the snapshot fields directly;
   cart-flow read sites continue to use the existing live aggregates
   and calculations, unchanged.

### 1. Denormalise key data

The principle: at every point that data resolves from an upstream row,
capture the resolved *value* onto the order, not a pointer back to the
upstream row. Already-snapshotted today:

- `LineItem.unit_price`, `LineItem.tax_rate`, `LineItem.product_name`,
  `LineItem.product_image_slug`, `LineItem.card_size` — captured at
  add-to-cart from the variant. A later product price/tax/name edit
  doesn't change history.
- `Order.fulfillment_amount`, `Order.fulfillment_method` — captured
  at submit_delivery from the chosen fulfillment option.

Added by this ADR:

- `Order.fulfillment_tax_rate` — captured at submit_delivery /
  update_fulfillment_option from
  `fulfillment_option.tax_rate.percentage`. Closes the Finland VAT
  exposure: a later edit to the rate row no longer alters what this
  order was quoted or charged. Also flows into the live calculation
  `fulfillment_tax_amount`, so even a cart in flight when VAT changes
  uses the rate it was originally quoted at.
- `Order.placed_line_total`, `placed_line_tax_amount`,
  `placed_discount_amount`, `placed_fulfillment_tax_amount`,
  `placed_tax_amount`, `placed_total` — captured at finalize_checkout
  from the cart's live aggregates and calculations. Concrete decimals
  on the placed row.
- `Order.placed_promotion_code` — captured at finalize_checkout from
  `order.promotion.code`. The `promotion_id` foreign key stays for
  reporting (which promotion was used); the *code as it was* is the
  authoritative answer for the customer-facing receipt.
- `LineItem.placed_line_total`, `placed_discount_amount`,
  `placed_line_tax_amount` — captured per-line-item at the parent's
  finalize_checkout. These were Ash calculations that depended on the
  live `order.promotion.discount_percentage`; concrete decimals after.

Capture is implemented by `Order.Changes.SnapshotTotals`, which runs in
`before_action` on `:finalize_checkout` while the order is still in
`:payment` state, loads the live aggregates and calculations, and
writes them as concrete attributes. The line-item snapshot writes via
the new `LineItem.snapshot_totals` action under the system actor.

### 2. Per-action policy lockdown

The previous broad `policy action_type(:update) do; authorize_if expr(state in @checkout_states); end`
is replaced with explicit per-action policies on Order:

- All cart-flow actions (`submit_*`, `return_to_*`,
  `update_fulfillment_option`, `add_card`, `remove_card`,
  `add_promotion_*`, `clear_promotion`, `set_gift`,
  `add_payment_intent_id`, `restart_checkout`) require
  `state in @checkout_states`. Once placed, none of these run, even via
  the owner.
- `:finalize_checkout` requires `state == :payment`.
- `:mark_payment_failed` requires `state in @checkout_states`. A failed
  payment is meaningful only mid-checkout; post-place refunds are a
  different concept (see "Future work" below).
- `:update_locale` is allowed always; it's presentational and doesn't
  violate the snapshot.

LineItem mirrors:

- `:create` requires `order.state != :placed`.
- `:read` allows cart-flow line items (public-by-id, since the order id
  is the session secret) and placed-order line items by their owner.
- `:update` / `:destroy` require `order.state != :placed`. Even the
  owner cannot mutate a placed order's line items.
- A `:system`-actor bypass lets `SnapshotTotals` write `placed_*`
  fields during `:finalize_checkout`.

### 3. Read sites

The order confirmation email — the only placed-order render path that
currently exists — reads `placed_*` fields directly. The
`SendOrderConfirmationEmail` worker no longer loads aggregates or
calculations; the values are flat attributes on the placed row.

Cart-flow code (`CheckoutLive`, the cart drawer in the layout)
continues to use the existing live aggregates and calculations on the
same field names. The snapshot fields exist alongside the live ones,
with disjoint usage.

## Consequences

### Benefits

- Placed orders are effectively immutable on cart-flow fields, enforced
  by Ash policies at the action layer rather than relying on
  convention.
- Numerical fidelity through upstream edits: VAT rate changes,
  promotion percentage edits, fulfillment option pricing edits — none
  retroactively change a placed order's totals.
- The snapshotting work is exactly what a future Cart/Order split
  would need for its conversion logic, so this ADR doesn't foreclose
  the split — it pre-pays half its cost.

### Trade-offs

- Two-namespace fields on the same row (`line_total` aggregate and
  `placed_line_total` stored attribute, etc.). Templates and read
  paths must know which namespace to use. Mitigation: cart-flow paths
  use the live aggregates exactly as before; placed-order read paths
  use `placed_*`.
- A failure mode where the snapshot doesn't run (e.g. a bug in
  `SnapshotTotals`) leaves a placed order with NULL `placed_*` fields,
  which the email template would render as blanks. Mitigation:
  test coverage on `SnapshotTotals` and the column nullability lets
  the application surface the bug rather than crash.
- The lockdown trusts the policy layer. Bypassing Ash actions (raw
  Ecto, `Ash.Seed.update!`, `:system` actor in the wrong place) can
  still mutate a placed order. Mitigation: the seam is at the action
  layer, which is the surface every legitimate code path goes through.

## How refunds, returns, and fulfillment work after this ADR

Following the same principle — placed Order is a snapshot, things that
*happen to* it after place go in sibling rows — the post-place
lifecycle uses separate concepts, not Order edits:

- **Payment status** stays on Order as `payment_status`
  (`:pending`, `:paid`, `:failed`, `:refunded`). The `:refunded`
  transition will be admin-only when refunds become real.
- **Fulfillment status** stays on Order as `fulfillment_status`
  (`:pending`, `:fulfilled`). Admin-only `:mark_fulfilled` will be
  added when fulfillment is operationalised.
- **Refunds** (when implemented) will be a new
  `Edenflowers.Store.Refund` resource with its own `amount`, `reason`,
  `created_at`, `belongs_to :order`. Order itself is never edited.
- **Returns** (when implemented) will be new `ReturnAuthorization`
  (and `Return`, `Reimbursement` if needed) resources. Order itself
  is never edited.

This is the same pattern used by Spree, Solidus, and Sylius — well-
trodden ground for the single-resource shape.

## What this ADR does *not* do

- Does not split Order into Cart + Order. See issue #149 for the
  analysis; revisit if any of its trigger features land.
- Does not introduce Refund or Return resources. Those remain future
  work; this ADR only sets up the immutable snapshot they will rely on.
- Does not backfill placed orders with `placed_*` values from before
  this migration. Existing placed orders continue to render via the
  live aggregates/calculations; they remain exposed to upstream edits
  until naturally aged out. (A backfill is straightforward if needed:
  iterate placed orders, compute and write `placed_*` values from
  current live state. Out of scope here.)
