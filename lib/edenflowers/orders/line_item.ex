defmodule Edenflowers.Orders.LineItem do
  use Ash.Resource,
    domain: Edenflowers.Orders,
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

      change Edenflowers.Orders.LineItem.Changes.PopulateFromVariant
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
      authorize_if Edenflowers.Orders.LineItem.Checks.OrderNotPlaced
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
    attribute :variant_size, Edenflowers.Catalog.ProductVariantSize
    timestamps()
  end

  relationships do
    belongs_to :order, Edenflowers.Orders.Order, allow_nil?: false
    belongs_to :product, Edenflowers.Catalog.Product, allow_nil?: false
    belongs_to :product_variant, Edenflowers.Catalog.ProductVariant, allow_nil?: false
  end

  calculations do
    calculate :promotion_applied?, :boolean, expr(not is_nil(order.promotion_id))

    calculate :subtotal, :decimal, expr(unit_price * quantity)

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

    calculate :tax, :decimal, expr(total * tax_rate)

    # `unit_price` is stored tax-inclusive.
    calculate :unit_price_ex_tax, :decimal, expr(unit_price / (1 + tax_rate))
  end

  identities do
    identity :unique_product_variant, [:order_id, :product_variant_id]
  end
end
