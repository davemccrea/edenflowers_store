defmodule Edenflowers.Store.LineItem do
  use Ash.Resource, domain: Edenflowers.Store, data_layer: AshPostgres.DataLayer

  postgres do
    repo Edenflowers.Repo
    table "line_items"

    references do
      reference :order, on_delete: :delete
    end
  end

  code_interface do
    define :add_item, action: :create
    define :remove_item, action: :remove_item
    define :increment_quantity, action: :increment_quantity
    define :decrement_quantity, action: :decrement_quantity
  end

  actions do
    defaults [:read]

    create :create do
      accept [
        :order_id,
        :product_id,
        :product_variant_id,
        :product_name,
        :product_image_slug,
        :quantity,
        :unit_price,
        :tax_rate
      ]
    end

    destroy :remove_item

    update :increment_quantity do
      change atomic_update(:quantity, expr(quantity + 1))
    end

    update :decrement_quantity do
      change atomic_update(:quantity, expr(if(quantity > 1, quantity - 1, quantity)))
    end
  end

  preparations do
    prepare build(load: [:line_subtotal])
  end

  attributes do
    uuid_primary_key :id
    attribute :quantity, :integer, default: 1, constraints: [min: 1]
    attribute :unit_price, :decimal, allow_nil?: false
    attribute :tax_rate, :decimal, allow_nil?: false
    attribute :product_name, :string, allow_nil?: false
    attribute :product_image_slug, :string, allow_nil?: false
    timestamps()
  end

  relationships do
    belongs_to :order, Edenflowers.Store.Order, allow_nil?: false
    belongs_to :product, Edenflowers.Store.Product, allow_nil?: false
    belongs_to :product_variant, Edenflowers.Store.ProductVariant, allow_nil?: false
  end

  calculations do
    calculate :promotion_applied?,
              :boolean,
              expr(
                if(
                  is_nil(order.promotion),
                  do: false,
                  else: true
                )
              )

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
