defmodule Edenflowers.Store.Order do
  use Ash.Resource, domain: Edenflowers.Store, data_layer: AshPostgres.DataLayer

  postgres do
    repo Edenflowers.Repo
    table "orders"
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:promotion_id]
      change set_attribute(:state, :cart)
    end

    update :complete do
      change atomic_update(:state, :completed)
    end

    update :add_promotion do
      argument :promotion_id, :uuid, allow_nil?: false
      change atomic_update(:promotion_id, expr(^arg(:promotion_id)))
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :state, Edenflowers.Store.OrderState, allow_nil?: false
    attribute :customer_name, :string
    attribute :customer_email, :string
    attribute :recipient_name, :string
    attribute :recipient_address, :string
    attribute :recipient_city, :string
    attribute :recipient_postal_code, :string
    attribute :recipient_phone_number, :string
    attribute :delivery_instructions, :string
    attribute :is_gift, :boolean
    attribute :gift_message, :string
    attribute :fulfillment_date, :date
    attribute :stripe_payment_id, :string
    attribute :fulfillment_amount, :decimal
    timestamps()
  end

  relationships do
    belongs_to :fulfillment_option, Edenflowers.Store.FulfillmentOption
    belongs_to :promotion, Edenflowers.Store.Promotion
    has_many :order_items, Edenflowers.Store.LineItem
  end

  calculations do
    calculate :promotion_applied?, :boolean, expr(not is_nil(promotion))
  end

  aggregates do
    sum :line_total, :order_items, :line_total
    sum :line_total_with_discount, :order_items, :line_total_with_discount
    sum :line_tax_amount, :order_items, :line_tax_amount
  end
end
