defmodule Edenflowers.Orders.Subscription do
  @moduledoc """
  A customer's standing request for a florist's-choice bouquet every few
  weeks. Not an order: it creates ordinary orders, its Occurrences, from the
  delivery details of the first one. See ADR 0003.
  """
  use Ash.Resource,
    domain: Edenflowers.Orders,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine, AshPaperTrail.Resource]

  @intervals [1, 2, 4]

  def intervals, do: @intervals

  postgres do
    repo Edenflowers.Repo
    table "subscriptions"
  end

  # Created only once the first order is paid, so it starts active. Pausing,
  # cancelling and failed charges arrive with occurrences and the account page.
  state_machine do
    initial_states([:active])
    default_initial_state(:active)
    extra_states([:paused, :payment_failed, :cancelled])
  end

  paper_trail do
    change_tracking_mode :changes_only
    store_action_name? true
    ignore_attributes [:inserted_at, :updated_at]
  end

  actions do
    defaults [:read]

    read :admin_list do
      pagination offset?: true, keyset?: true, countable: true, required?: false
      prepare build(sort: [next_fulfillment_date: :asc], load: [:user, :product_variant])
    end

    create :activate do
      accept [
        :user_id,
        :product_variant_id,
        :interval_weeks,
        :next_fulfillment_date,
        :recipient_name,
        :recipient_phone_number,
        :delivery_address,
        :delivery_instructions,
        :fulfillment_option_id,
        :card_message,
        :locale,
        :stripe_customer_id,
        :stripe_payment_method_id
      ]

      validate attribute_in(:interval_weeks, @intervals)
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if action_type(:read)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :interval_weeks, :integer, allow_nil?: false
    attribute :next_fulfillment_date, :date, allow_nil?: false
    attribute :skipped_dates, {:array, :date}, allow_nil?: false, default: []

    # Copied from the first order. Each occurrence prices its fee afresh from
    # the address, so no fee or geocode is kept here.
    attribute :recipient_name, :string
    attribute :recipient_phone_number, :string
    attribute :delivery_address, :string
    attribute :delivery_instructions, :string
    attribute :card_message, :string
    attribute :locale, :string, allow_nil?: false

    attribute :stripe_customer_id, :string, allow_nil?: false
    attribute :stripe_payment_method_id, :string, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :user, Edenflowers.Accounts.User, allow_nil?: false
    belongs_to :product_variant, Edenflowers.Catalog.ProductVariant, allow_nil?: false
    belongs_to :fulfillment_option, Edenflowers.Fulfillment.FulfillmentOption, allow_nil?: false
    has_many :orders, Edenflowers.Orders.Order
  end
end
