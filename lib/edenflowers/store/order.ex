defmodule Edenflowers.Store.Order do
  use Ash.Resource,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    notifiers: [Ash.Notifier.PubSub]

  use Gettext, backend: EdenflowersWeb.Gettext

  @load [
    :total_items_in_cart,
    :promotion_applied?,
    :discount_amount,
    :total,
    :tax_amount,
    :line_items,
    :promotion
  ]

  postgres do
    repo Edenflowers.Repo
    table "orders"
  end

  code_interface do
    define :get_order_for_checkout, action: :get_order_for_checkout, args: [:id]
    define :add_payment_intent_id, action: :add_payment_intent_id, args: [:payment_intent_id]
    define :add_promotion, action: :add_promotion, args: [:promotion_id]
    define :clear_promotion, action: :clear_promotion
  end

  actions do
    defaults [:read, :destroy]

    read :get_order_for_checkout do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true
      prepare build(load: @load)
    end

    create :create do
      accept [:promotion_id, :fulfillment_option_id]
      change set_attribute(:step, 1)
      change load(@load)
    end

    # Step 1 - Your Details
    update :edit_step_1 do
      change set_attribute(:step, 1)
      change load(@load)
    end

    # Step 2 - Gift Options
    update :edit_step_2 do
      change set_attribute(:step, 2)
      change load(@load)
    end

    # Step 3 - Delivery Information
    update :edit_step_3 do
      change set_attribute(:step, 3)
      change load(@load)
    end

    # Step 1 - Your Details
    update :save_step_1 do
      accept [:customer_name, :customer_email]
      require_attributes [:customer_name, :customer_email]
      change set_attribute(:step, 2)
      change load(@load)
      require_atomic? false

      validate match(:customer_email, ~r/\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b/i) do
        message gettext("must be valid email address")
      end
    end

    # Step 2 - Gift Options
    update :save_step_2 do
      accept [:is_gift, :gift_message]
      change set_attribute(:step, 3)
      change load(@load)
    end

    # Step 3 - Delivery Information
    update :save_step_3 do
      accept [
        :fulfillment_option_id,
        :recipient_name,
        :recipient_phone_number,
        :delivery_address,
        :delivery_instructions,
        :fulfillment_date,
        :fulfillment_amount,
        :calculated_address,
        :here_id,
        :distance,
        :position
      ]

      change set_attribute(:step, 4)
      change load(@load)
    end

    update :save_step_4 do
      accept []
    end

    update :add_payment_intent_id do
      accept [:payment_intent_id]
      change load(@load)
    end

    update :add_promotion do
      argument :promotion_id, :uuid, allow_nil?: false
      change atomic_update(:promotion_id, expr(^arg(:promotion_id)))
      change load(@load)
    end

    update :clear_promotion do
      change set_attribute(:promotion_id, nil)
      change load(@load)
    end
  end

  pub_sub do
    module EdenflowersWeb.Endpoint
    publish_all :update, ["order", "updated", :_pkey]
  end

  attributes do
    uuid_primary_key :id

    attribute :step, :integer, default: 1, constraints: [min: 1, max: 4]

    # Step 1 - Your Details
    attribute :customer_name, :string
    attribute :customer_email, :string

    # Step 2 - Gift Options
    attribute :is_gift, :boolean
    attribute :gift_message, :string

    # Step 3 - Delivery Information
    attribute :recipient_name, :string
    attribute :recipient_phone_number, :string
    attribute :delivery_address, :string
    attribute :delivery_instructions, :string
    attribute :fulfillment_date, :date

    attribute :fulfillment_amount, :decimal
    attribute :calculated_address, :string
    attribute :here_id, :string
    attribute :distance, :integer
    attribute :position, :string

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
    calculate :total, :decimal, expr(line_total + (fulfillment_amount || 0))

    calculate :fulfillment_tax_amount,
              :decimal,
              expr((fulfillment_amount || 0) * fulfillment_option.tax_rate.percentage)

    calculate :tax_amount, :decimal, expr(line_tax_amount + fulfillment_tax_amount)
  end

  aggregates do
    sum :total_items_in_cart, :line_items, :quantity
    sum :line_total, :line_items, :line_total
    sum :line_tax_amount, :line_items, :line_tax_amount
    sum :discount_amount, :line_items, :discount_amount
  end
end
