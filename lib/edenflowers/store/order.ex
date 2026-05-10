defmodule Edenflowers.Store.Order do
  @moduledoc """
  An immutable record of a placed order. Created exclusively by
  `Cart.Changes.ConvertToOrder` at place-time, as a snapshot of a
  `Edenflowers.Store.Cart` and its `CartLineItem` rows. The cart row is kept
  for audit/refund linkage.

  No checkout-flow state machine. No `submit_*` / `return_to_*` actions. The
  only mutable surface is the post-place lifecycle:

    * `payment_status`: driven by `mark_paid` / `mark_failed` /
      `mark_refunded` (today only `mark_refunded` is post-conversion; paid
      is set by the conversion itself; failed remains on the Cart since
      conversion only fires on success).
    * `fulfillment_status`: driven by `mark_fulfilled`.

  Snapshot fields are write-once at `:place_from_cart` and never edited.
  See docs/adr/0001-split-order-into-cart-and-order.md for the invariants
  the snapshot must preserve.
  """

  use Ash.Resource,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Store.FulfillmentOption

  postgres do
    repo Edenflowers.Repo
    table "orders"
  end

  code_interface do
    define :get_by_id, action: :by_id, args: [:id]
    define :get_by_order_reference, action: :by_order_reference, args: [:order_reference]
    define :get_for_confirmation, action: :for_confirmation, args: [:id]
    define :get_all_completed, action: :completed, args: [:user_id]
    define :place_from_cart, action: :place_from_cart
    define :mark_refunded, action: :mark_refunded
    define :mark_fulfilled, action: :mark_fulfilled
  end

  actions do
    defaults [:read]

    read :by_id do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true
    end

    read :by_order_reference do
      argument :order_reference, :string, allow_nil?: false
      filter expr(order_reference == ^arg(:order_reference))
      get? true
    end

    read :for_confirmation do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true

      prepare build(
                load: [
                  :promotion,
                  fulfillment_option: [:tax_rate],
                  line_items: []
                ]
              )
    end

    read :completed do
      argument :user_id, :uuid, allow_nil?: false
      filter expr(user_id == ^arg(:user_id))
    end

    # The only path to creating an Order. Called exclusively by
    # Cart.Changes.ConvertToOrder under the system actor.
    create :place_from_cart do
      accept [
        :order_reference,
        :user_id,
        :payment_intent_id,
        :ordered_at,
        :payment_status,
        :fulfillment_status,
        :customer_name,
        :customer_email,
        :gift,
        :card_message,
        :recipient_name,
        :recipient_phone_number,
        :delivery_address,
        :delivery_instructions,
        :fulfillment_date,
        :fulfillment_amount,
        :fulfillment_method,
        :geocoded_address,
        :here_id,
        :distance,
        :position,
        :locale,
        :line_total,
        :line_tax_amount,
        :discount_amount,
        :fulfillment_tax_amount,
        :tax_amount,
        :total,
        :promotion_id,
        :fulfillment_option_id
      ]
    end

    update :mark_refunded do
      validate attribute_equals(:payment_status, :paid)
      change set_attribute(:payment_status, :refunded)
    end

    update :mark_fulfilled do
      validate attribute_equals(:fulfillment_status, :pending)
      change set_attribute(:fulfillment_status, :fulfilled)
    end
  end

  policies do
    # System bypass - for webhooks and background jobs (creation, email send).
    bypass actor_attribute_equals(:system, true) do
      authorize_if always()
    end

    # Admin bypass - admins can do anything
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Creation is system-only (only the conversion change creates orders).
    policy action_type(:create) do
      authorize_if actor_attribute_equals(:system, true)
    end

    # Owner-only reads.
    policy action_type(:read) do
      authorize_if expr(user_id == ^actor(:id))
    end

    # Mutations on placed orders are admin-only (covered by the bypass above).
    policy action_type(:update) do
      authorize_if actor_attribute_equals(:admin, true)
    end
  end

  attributes do
    uuid_primary_key :id

    attribute :order_reference, :string, allow_nil?: false

    # Snapshot of when the cart was converted.
    attribute :ordered_at, :utc_datetime, allow_nil?: false

    attribute :payment_status, :atom,
      allow_nil?: false,
      default: :paid,
      constraints: [
        one_of: [
          :paid,
          :refunded
        ]
      ]

    attribute :fulfillment_status, :atom,
      allow_nil?: false,
      default: :pending,
      constraints: [
        one_of: [
          :pending,
          :fulfilled
        ]
      ]

    # Stripe linkage — kept for refunds and reconciliation.
    attribute :payment_intent_id, :string, allow_nil?: false

    # Snapshot fields — frozen at place-time. See ADR for invariants.
    attribute :customer_name, :string, allow_nil?: false
    attribute :customer_email, :string, allow_nil?: false

    attribute :gift, :boolean, default: false, allow_nil?: false
    attribute :card_message, :string

    attribute :recipient_name, :string
    attribute :recipient_phone_number, :string
    attribute :delivery_address, :string
    attribute :delivery_instructions, :string
    attribute :fulfillment_date, :date
    attribute :fulfillment_amount, :decimal
    attribute :fulfillment_method, FulfillmentOption.FulfillmentMethod
    attribute :geocoded_address, :string
    attribute :here_id, :string
    attribute :distance, :integer
    attribute :position, :string

    attribute :locale, :string, allow_nil?: false, default: "sv-FI"

    # Snapshotted totals — concrete values, not computed from line items.
    # A later promotion edit must not retroactively change these.
    attribute :line_total, :decimal, allow_nil?: false
    attribute :line_tax_amount, :decimal, allow_nil?: false
    attribute :discount_amount, :decimal, allow_nil?: false, default: Decimal.new(0)
    attribute :fulfillment_tax_amount, :decimal, allow_nil?: false, default: Decimal.new(0)
    attribute :tax_amount, :decimal, allow_nil?: false
    attribute :total, :decimal, allow_nil?: false

    timestamps()
  end

  relationships do
    belongs_to :user, Edenflowers.Accounts.User
    belongs_to :fulfillment_option, Edenflowers.Store.FulfillmentOption
    belongs_to :promotion, Edenflowers.Store.Promotion
    has_many :line_items, Edenflowers.Store.OrderLineItem
  end

  calculations do
    calculate :promotion_applied?, :boolean, expr(not is_nil(promotion_id))
  end

  identities do
    identity :unique_order_reference, [:order_reference]
  end
end
