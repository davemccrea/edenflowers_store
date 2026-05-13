defmodule Edenflowers.Store.LineItem do
  use Ash.Resource,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    repo Edenflowers.Repo
    table "line_items"

    references do
      reference :order, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    create :add_to_cart do
      accept [:order_id, :product_variant_id, :quantity, :is_card]

      upsert? true
      upsert_identity :unique_product_variant
      upsert_fields [:quantity]

      change Edenflowers.Store.LineItem.Changes.PopulateFromVariant
      change atomic_update(:quantity, expr(quantity + ^atomic_ref(:quantity)))
    end

    destroy :remove_item do
      require_atomic? false
    end

    update :increment_quantity do
      change atomic_update(:quantity, expr(quantity + 1))
    end

    update :decrement_quantity do
      change atomic_update(:quantity, expr(if(quantity > 1, quantity - 1, quantity)))
    end

    # Freezes the live aggregates into `placed_*` columns. Called from
    # `Order.Changes.SnapshotTotals` during `:finalize_checkout`, before
    # the parent order transitions to `:placed`. Guarded by policy so no
    # other caller can write these columns.
    update :snapshot_totals do
      accept [:placed_line_total, :placed_discount_amount, :placed_line_tax_amount]
    end
  end

  policies do
    # Admin/system can always read (admin views, background workers loading
    # placed orders' line items for the confirmation email). Mutations to
    # placed orders go through sibling resources per ADR 0001, so neither
    # actor is bypassed for updates/destroys.
    bypass actor_attribute_equals(:admin, true) do
      authorize_if action_type(:read)
    end

    bypass actor_attribute_equals(:system, true) do
      authorize_if action_type(:read)
    end

    # Snapshot freezes placed_* columns; only the system actor (used by
    # `Order.Changes.SnapshotTotals`) may invoke it, and only while the
    # parent order is still in :payment. After that the row is immutable
    # to every actor.
    policy action(:snapshot_totals) do
      forbid_if expr(order.state != :payment)
      authorize_if actor_attribute_equals(:system, true)
    end

    # Add to cart only while the order is in checkout flow. The card
    # variant is gated at the order level via Order.add_card.
    policy action_type(:create) do
      authorize_if expr(order.state != :placed)
    end

    policy action_type(:read) do
      # Guest checkout: anyone can work with line items for orders still in
      # the checkout flow (any sub-state before :placed).
      authorize_if expr(order.state != :placed)
      # Placed orders: only the owner can read their line items.
      authorize_if expr(order.state == :placed and order.user_id == ^actor(:id))
    end

    # Placed orders are immutable to every actor; mutations during checkout
    # flow are allowed via the existing cart actions.
    policy action_type([:update, :destroy]) do
      forbid_if expr(order.state == :placed)
      authorize_if always()
    end
  end

  pub_sub do
    module EdenflowersWeb.Endpoint

    publish_all :create, ["line_item", "changed", :order_id]
    publish_all :update, ["line_item", "changed", :order_id]
    publish_all :destroy, ["line_item", "changed", :order_id], previous_values?: true
  end

  preparations do
    prepare build(load: [:line_subtotal], sort: [inserted_at: :asc])
  end

  attributes do
    uuid_primary_key :id
    attribute :quantity, :integer, default: 1, constraints: [min: 1]
    attribute :unit_price, :decimal, allow_nil?: false
    attribute :tax_rate, :decimal, allow_nil?: false
    attribute :product_name, :string, allow_nil?: false
    attribute :product_image_slug, :string, allow_nil?: false
    attribute :is_card, :boolean, default: false, allow_nil?: false
    attribute :variant_size, Edenflowers.Store.ProductVariantSize

    # Snapshot of the live aggregates at finalize_checkout. Nullable so
    # pre-snapshot rows aren't broken; new placed orders always populate
    # them via `:snapshot_totals`.
    attribute :placed_line_total, :decimal
    attribute :placed_discount_amount, :decimal
    attribute :placed_line_tax_amount, :decimal

    timestamps()
  end

  relationships do
    belongs_to :order, Edenflowers.Store.Order, allow_nil?: false
    belongs_to :product, Edenflowers.Store.Product, allow_nil?: false
    belongs_to :product_variant, Edenflowers.Store.ProductVariant, allow_nil?: false
  end

  calculations do
    calculate :promotion_applied?, :boolean, expr(not is_nil(order.promotion_id))

    # This is the base price for a specific item or service multiplied by the quantity, before any taxes or discounts are applied.
    calculate :line_subtotal, :decimal, expr(unit_price * quantity)

    # This is the final amount for a specific line item, including the subtotal plus taxes and minus any line-specific discounts.
    calculate :line_total,
              :decimal,
              expr(
                if(
                  promotion_applied?,
                  do: line_subtotal - discount_amount,
                  else: line_subtotal
                )
              )

    calculate :discount_amount,
              :decimal,
              expr(
                if(
                  promotion_applied?,
                  do: line_subtotal * order.promotion.discount_percentage,
                  else: 0
                )
              )

    # This is the amount of tax applied to a specific line item.
    calculate :line_tax_amount, :decimal, expr(line_total * tax_rate)
  end

  identities do
    identity :unique_product_variant, [:order_id, :product_variant_id]
  end
end
