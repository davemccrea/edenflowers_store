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
    attribute :quantity, :integer, allow_nil?: false, default: 1, constraints: [min: 1]
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

    calculate :line_total, :decimal, expr(unit_price * quantity)

    calculate :line_total_with_discount,
              :decimal,
              expr(
                if(
                  promotion_applied?,
                  do: line_total * (1 - order.promotion.discount_percentage),
                  else: line_total
                )
              )

    calculate :line_tax_amount,
              :decimal,
              expr(
                if(
                  promotion_applied?,
                  do: line_total_with_discount * tax_rate,
                  else: line_total * tax_rate
                )
              )
  end
end
