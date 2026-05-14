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
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if action_type(:read)
    end

    policy action_type(:read) do
      authorize_if expr(order.state != :placed)
      authorize_if expr(order.state == :placed and order.user_id == ^actor(:id))
    end

    # Filter expressions can't authorize creates (no row to filter yet), so a
    # custom check resolves the parent order's state at evaluation time.
    policy action_type(:create) do
      authorize_if Edenflowers.Store.LineItem.Checks.OrderNotPlaced
    end

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
    prepare build(load: [:subtotal], sort: [inserted_at: :asc])
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
    calculate :subtotal, :decimal, expr(unit_price * quantity)

    # This is the final amount for a specific line item, including the subtotal plus taxes and minus any line-specific discounts.
    calculate :total,
              :decimal,
              expr(
                if(
                  promotion_applied?,
                  do: subtotal - discount,
                  else: subtotal
                )
              )

    calculate :discount,
              :decimal,
              expr(
                if(
                  promotion_applied?,
                  do: subtotal * order.discount_rate,
                  else: 0
                )
              )

    # This is the amount of tax applied to a specific line item.
    calculate :tax, :decimal, expr(total * tax_rate)
  end

  identities do
    identity :unique_product_variant, [:order_id, :product_variant_id]
  end
end
