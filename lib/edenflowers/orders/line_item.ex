defmodule Edenflowers.Orders.LineItem do
  use Ash.Resource,
    domain: Edenflowers.Orders,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    repo Edenflowers.Repo
    table "line_items"
    migration_types unit_price: :decimal

    check_constraints do
      check_constraint :unit_price, "line_items_valid_unit_price",
        check: "unit_price >= 0 AND unit_price = round(unit_price, 2)",
        message: "must be a non-negative amount in whole cents"

      check_constraint :product_variant_id, "line_items_catalogue_lines_have_a_product",
        check: "(product_variant_id IS NULL) = (product_id IS NULL)",
        message: "must name both the product and its variant, or neither"
    end

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

      change Edenflowers.Orders.Changes.PopulateFromVariant
      change Edenflowers.Orders.Changes.KeepSubscriptionAlone
      change atomic_update(:quantity, expr(quantity + ^atomic_ref(:quantity)))
    end

    # A line on a custom order that Jennie describes and prices herself, with
    # no product behind it.
    create :add_custom_item do
      accept [:order_id, :product_name, :unit_price, :tax_rate, :quantity]
    end

    # The destroy notification publishes to the removed item's order_id topic.
    destroy :remove_item do
      require_atomic? false
    end

    # A subscription is for one bouquet each time.
    update :increment_quantity do
      change atomic_update(:quantity, expr(if(subscribable, quantity, quantity + 1)))
    end

    update :decrement_quantity do
      change atomic_update(:quantity, expr(if(quantity > 1, quantity - 1, quantity)))
    end

    update :set_quantity do
      accept [:quantity]
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
      authorize_if Edenflowers.Orders.Checks.OrderNotPlaced
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
    attribute :quantity, :integer, allow_nil?: false, default: 1, constraints: [min: 1]
    attribute :unit_price, :decimal, allow_nil?: false, constraints: [min: 0, scale: 2]
    attribute :tax_rate, :decimal, allow_nil?: false
    attribute :product_name, :string, allow_nil?: false
    # Nil for a custom item, which has no product photo.
    attribute :product_image_slug, :string
    attribute :is_card, :boolean, default: false, allow_nil?: false
    # Snapshotted from the product, so unflagging it later leaves existing orders' fees alone.
    attribute :free_delivery, :boolean, default: false, allow_nil?: false
    attribute :subscribable, :boolean, default: false, allow_nil?: false
    attribute :variant_size, Edenflowers.Catalog.ProductVariantSize
    timestamps()
  end

  relationships do
    belongs_to :order, Edenflowers.Orders.Order, allow_nil?: false
    # Both nil for a custom item.
    belongs_to :product, Edenflowers.Catalog.Product
    belongs_to :product_variant, Edenflowers.Catalog.ProductVariant
  end

  calculations do
    calculate :promotion_applied?, :boolean, expr(order.promotion_applied?)

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
                  do: round(subtotal * order.discount_rate, 2),
                  else: 0
                )
              )

    # `unit_price` is stored tax-inclusive.
    calculate :unit_price_ex_tax, :decimal, expr(round(unit_price / (1 + tax_rate), 2))
  end

  identities do
    identity :unique_product_variant, [:order_id, :product_variant_id]
  end
end
