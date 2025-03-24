defmodule Edenflowers.Store.LineItem do
  use Ash.Resource, domain: Edenflowers.Store, data_layer: AshPostgres.DataLayer

  postgres do
    repo Edenflowers.Repo
    table "line_items"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:order_id, :product_variant_id, :quantity, :unit_price, :tax_rate]
    end

    update :increment_quantity do
      change atomic_update(:quantity, expr(quantity + 1))
    end

    update :decrement_quantity do
      change atomic_update(:quantity, expr(if(quantity > 1, quantity - 1, quantity)))
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :quantity, :integer, default: 1, constraints: [min: 1]
    attribute :unit_price, :decimal, allow_nil?: false
    attribute :tax_rate, :decimal, allow_nil?: false
    timestamps()
  end

  relationships do
    belongs_to :order, Edenflowers.Store.Order, allow_nil?: false
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
                  do: line_subtotal * (1 - order.promotion.discount_percentage),
                  else: line_subtotal
                )
              )

    # This is the amount of tax applied to a specific line item.
    calculate :line_tax_amount, :decimal, expr(line_total * tax_rate)
  end
end
