defmodule Edenflowers.Store.CartLineItem do
  @moduledoc """
  A mutable line item belonging to a `Cart`. Add/remove/increment/decrement
  during checkout. At conversion time, `Cart.Changes.ConvertToOrder`
  snapshots each `CartLineItem` into a fresh `OrderLineItem`; the cart line
  items remain on the cart row for audit/refund linkage.
  """

  use Ash.Resource,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

  postgres do
    repo Edenflowers.Repo
    table "cart_line_items"

    references do
      reference :cart, on_delete: :delete
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
      accept [:cart_id, :product_variant_id, :quantity, :is_card]

      upsert? true
      upsert_identity :unique_product_variant
      upsert_fields [:quantity]

      change Edenflowers.Store.CartLineItem.Changes.PopulateFromVariant
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
      authorize_if always()
    end

    # Allow creating cart line items without authentication. The card variant
    # is gated at the cart level via Cart.add_card.
    policy action_type(:create) do
      authorize_if always()
    end

    # Read/Update/Destroy access:
    # Cart line items are public-by-id while the cart is in checkout.
    # Once the cart is :converted, the cart line items become an audit record
    # — only the owner can read them.
    policy action_type([:read, :update, :destroy]) do
      authorize_if expr(cart.state != :converted)
      authorize_if expr(cart.state == :converted and cart.user_id == ^actor(:id))
    end
  end

  pub_sub do
    module EdenflowersWeb.Endpoint

    publish_all :create, ["cart_line_item", "changed", :cart_id]
    publish_all :update, ["cart_line_item", "changed", :cart_id]
    publish_all :destroy, ["cart_line_item", "changed", :cart_id], previous_values?: true
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
    timestamps()
  end

  relationships do
    belongs_to :cart, Edenflowers.Store.Cart, allow_nil?: false
    belongs_to :product, Edenflowers.Store.Product, allow_nil?: false
    belongs_to :product_variant, Edenflowers.Store.ProductVariant, allow_nil?: false
  end

  calculations do
    calculate :promotion_applied?, :boolean, expr(not is_nil(cart.promotion_id))

    calculate :line_subtotal, :decimal, expr(unit_price * quantity)

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
                  do: line_subtotal * cart.promotion.discount_percentage,
                  else: 0
                )
              )

    calculate :line_tax_amount, :decimal, expr(line_total * tax_rate)
  end

  identities do
    identity :unique_product_variant, [:cart_id, :product_variant_id]
  end
end
