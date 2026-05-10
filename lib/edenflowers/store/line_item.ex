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

  code_interface do
    define :add_item, action: :add_to_cart
    define :remove_item, action: :remove_item
    define :increment_quantity, action: :increment_quantity
    define :decrement_quantity, action: :decrement_quantity
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

    # Called once per line item by Order.Changes.SnapshotTotals at
    # :finalize_checkout, under the system actor. The :update policy
    # forbids non-system writes once order.state == :placed, so this
    # action is the only path that can write the placed_* fields, and
    # SnapshotTotals runs while the order is still in :payment state
    # (which is :placed-not-yet) — both the policy bypass for :system and
    # the still-cart-state of the parent let it through.
    update :snapshot_totals do
      accept [:placed_line_total, :placed_discount_amount, :placed_line_tax_amount]
    end
  end

  policies do
    # System bypass - SnapshotTotals on the parent order writes placed_* on
    # line items via a system-actor update.
    bypass actor_attribute_equals(:system, true) do
      authorize_if always()
    end

    # Admin bypass - admins can do anything
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Create only allowed when the parent order is still in checkout. After
    # the order is :placed, no new line items can attach. The card variant
    # is gated at the order level via Order.add_card.
    policy action_type(:create) do
      authorize_if expr(order.state != :placed)
    end

    # Reads: cart-flow line items are public-by-id (the order id is the
    # session secret); placed-order line items are owner-only.
    policy action_type(:read) do
      authorize_if expr(order.state != :placed)
      authorize_if expr(order.state == :placed and order.user_id == ^actor(:id))
    end

    # Update / Destroy: never allowed once the parent order is placed —
    # not even by the owner. Spree-style "complete = locked." The
    # `placed_*` snapshot fields are only writable by the system actor
    # (SnapshotTotals during finalize_checkout), so the bypass above
    # covers the legitimate write path.
    policy action_type([:update, :destroy]) do
      authorize_if expr(order.state != :placed)
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
    attribute :card_size, Edenflowers.Store.ProductVariantSize

    # Snapshot fields. NULL until the parent order is placed; populated by
    # Order.Changes.SnapshotTotals at :finalize_checkout and never edited
    # again. After place, these are the authoritative values: a later edit
    # to `order.promotion.discount_percentage` or to a `tax_rate` row
    # cannot retroactively change what this line item shows on the receipt.
    #
    # `unit_price` and `tax_rate` are already snapshotted by
    # Changes.PopulateFromVariant at add-to-cart time. `placed_*` covers
    # the *derived* numbers that depend on order-level inputs (the active
    # promotion, the order's tax context).
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
