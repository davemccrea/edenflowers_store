defmodule Edenflowers.Store.Order do
  use Ash.Resource,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer

  postgres do
    repo Edenflowers.Repo
    table "orders"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:promotion_id, :fulfillment_option_id]
      change set_attribute(:step, 1)
    end

    update :edit_step_1 do
      change set_attribute(:step, 1)
    end

    update :edit_step_2 do
      change set_attribute(:step, 2)
    end

    update :edit_step_3 do
      change set_attribute(:step, 3)
    end

    update :save_step_1 do
      accept [
        :fulfillment_option_id,
        :fulfillment_date,
        :recipient_phone_number,
        :delivery_address,
        :delivery_instructions,
        :fulfillment_amount,
        :calculated_address,
        :here_id,
        :distance,
        :position
      ]

      change set_attribute(:step, 2)
    end

    update :save_step_2 do
      accept [:gift_message]

      change set_attribute(:step, 3)
    end

    update :save_step_3 do
      accept []
      # TODO: should state be :cart and :order, instead of :cart and :completed?
      change set_attribute(:state, :completed)
    end

    update :add_payment_intent_id do
      accept [:payment_intent_id]
    end

    update :add_promotion do
      argument :promotion_id, :uuid, allow_nil?: false
      change atomic_update(:promotion_id, expr(^arg(:promotion_id)))
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :state, Edenflowers.Store.OrderState, default: :cart, allow_nil?: false

    attribute :step, :integer, default: 1, constraints: [min: 1, max: 3]

    # Step 1 - Delivery
    attribute :recipient_phone_number, :string
    attribute :delivery_address, :string
    attribute :delivery_instructions, :string
    attribute :fulfillment_date, :date
    attribute :fulfillment_amount, :decimal
    attribute :calculated_address, :string
    attribute :here_id, :string
    attribute :distance, :integer
    attribute :position, :string

    # Step 2 - Customise
    attribute :gift_message, :string

    # Step 3 - Payment
    attribute :customer_name, :string
    attribute :customer_email, :string
    attribute :payment_intent_id, :string

    timestamps()
  end

  relationships do
    belongs_to :fulfillment_option, Edenflowers.Store.FulfillmentOption
    belongs_to :promotion, Edenflowers.Store.Promotion
    has_many :line_items, Edenflowers.Store.LineItem
  end

  calculations do
    calculate :promotion_applied?, :boolean, expr(not is_nil(promotion))
    calculate :total, :decimal, expr(line_total + fulfillment_amount)
    calculate :fulfillment_tax_amount, :decimal, expr(fulfillment_amount * fulfillment_option.tax_rate.percentage)
    calculate :tax_amount, :decimal, expr(line_tax_amount + fulfillment_tax_amount)
  end

  aggregates do
    sum :total_items_in_cart, :line_items, :quantity
    sum :line_total, :line_items, :line_total
    sum :line_tax_amount, :line_items, :line_tax_amount
    sum :discount_amount, :line_items, :discount_amount
  end
end
