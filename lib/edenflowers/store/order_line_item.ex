defmodule Edenflowers.Store.OrderLineItem do
  @moduledoc """
  An immutable line item belonging to an `Order`. Created exclusively by
  `Cart.Changes.ConvertToOrder` at place-time as a snapshot of a
  `CartLineItem`. No update or destroy actions exist; the values are frozen
  for the lifetime of the order.

  The numeric fields (`line_total`, `discount_amount`, `line_tax_amount`)
  are stored as concrete values rather than recomputed from the cart's
  promotion — see the conversion change for the invariants.
  """

  use Ash.Resource,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo Edenflowers.Repo
    table "order_line_items"

    references do
      reference :order, on_delete: :delete
    end
  end

  actions do
    defaults [:read]

    # The only path to creating an OrderLineItem. Called exclusively by
    # Cart.Changes.ConvertToOrder under the system actor.
    create :snapshot_from_cart do
      accept [
        :order_id,
        :product_id,
        :product_variant_id,
        :quantity,
        :unit_price,
        :tax_rate,
        :product_name,
        :product_image_slug,
        :is_card,
        :card_size,
        :line_total,
        :discount_amount,
        :line_tax_amount
      ]
    end
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if always()
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # System-only creation (only the conversion change creates these).
    policy action_type(:create) do
      authorize_if actor_attribute_equals(:system, true)
    end

    # Owner-only reads.
    policy action_type(:read) do
      authorize_if expr(order.user_id == ^actor(:id))
    end
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

    # Snapshot values — see Cart.Changes.ConvertToOrder.
    attribute :line_total, :decimal, allow_nil?: false
    attribute :discount_amount, :decimal, default: Decimal.new(0), allow_nil?: false
    attribute :line_tax_amount, :decimal, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :order, Edenflowers.Store.Order, allow_nil?: false
    belongs_to :product, Edenflowers.Store.Product, allow_nil?: false
    belongs_to :product_variant, Edenflowers.Store.ProductVariant, allow_nil?: false
  end

  calculations do
    calculate :line_subtotal, :decimal, expr(unit_price * quantity)
  end
end
