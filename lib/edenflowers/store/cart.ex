defmodule Edenflowers.Store.Cart do
  @moduledoc """
  The customer's evolving cart-during-checkout. Mutable, browser-owned via the
  session cookie. Owns the form-progress state machine
  (`:contact_details → :gift_options → :delivery → :payment → :converted`) and
  every action the LiveView form layer drives.

  At place-time, `Cart.convert/2` snapshots the cart's fields and line items
  into a fresh `Edenflowers.Store.Order` (and `Edenflowers.Store.OrderLineItem`
  rows) and transitions the cart to `:converted`. The cart row is kept after
  conversion for audit/refund linkage; the order is the immutable source of
  truth from then on.
  """

  use Ash.Resource,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshStateMachine]

  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Ash.Resource.Change.Builtins

  alias __MODULE__.{Changes, Validations}
  alias Edenflowers.Store.FulfillmentOption

  @locales Edenflowers.Locales.all()

  @checkout_load [
    :total_items_in_cart,
    :discount_amount,
    :line_total,
    :line_tax_amount,
    :promotion_applied?,
    :total,
    :tax_amount,
    :fulfillment_tax_amount,
    :cart_effectively_empty?,
    :promotion,
    :fulfillment_option,
    :line_items
  ]

  postgres do
    repo Edenflowers.Repo
    table "carts"
  end

  @checkout_states [:contact_details, :gift_options, :delivery, :payment]

  state_machine do
    initial_states([:contact_details])
    default_initial_state(:contact_details)

    transitions do
      transition(:submit_contact_details, from: :contact_details, to: :gift_options)
      transition(:submit_gift_options, from: :gift_options, to: :delivery)
      transition(:submit_delivery, from: :delivery, to: :payment)
      transition(:convert, from: :payment, to: :converted)

      transition(:return_to_contact_details, from: [:gift_options, :delivery, :payment], to: :contact_details)
      transition(:return_to_gift_options, from: [:delivery, :payment], to: :gift_options)
      transition(:return_to_delivery, from: :payment, to: :delivery)

      transition(:restart_checkout, from: @checkout_states, to: :contact_details)
    end
  end

  code_interface do
    define :create_for_checkout, action: :create_for_checkout
    define :get_by_id, action: :by_id, args: [:id]
    define :get_for_checkout, action: :for_checkout, args: [:id]
    define :submit_contact_details, action: :submit_contact_details
    define :submit_gift_options, action: :submit_gift_options
    define :submit_delivery, action: :submit_delivery
    define :return_to_contact_details, action: :return_to_contact_details
    define :return_to_gift_options, action: :return_to_gift_options
    define :return_to_delivery, action: :return_to_delivery
    define :convert, action: :convert
    define :mark_payment_failed, action: :mark_payment_failed
    define :add_payment_intent_id, action: :add_payment_intent_id, args: [:payment_intent_id]
    define :add_promotion_with_id, action: :add_promotion_with_id, args: [:promotion_id]
    define :add_promotion_with_code, action: :add_promotion_with_code, args: [:code]
    define :clear_promotion, action: :clear_promotion
    define :update_fulfillment_option, action: :update_fulfillment_option, args: [:fulfillment_option_id]
    define :set_gift, action: :set_gift, args: [:gift]
    define :update_locale, action: :update_locale, args: [:locale]
    define :restart_checkout, action: :restart_checkout
    define :add_card, action: :add_card, args: [:product_variant_id]
    define :remove_card, action: :remove_card
  end

  actions do
    defaults [:read]

    # Read Actions
    read :by_id do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true
    end

    read :for_checkout do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true
      prepare build(load: @checkout_load)
    end

    # Create Actions
    create :create_for_checkout do
      # Order reference is generated here on the cart so it can flow through
      # to Stripe metadata / customer-facing surfaces *before* conversion.
      # Conversion copies the same reference onto the Order, so the customer
      # sees a stable string from "started checkout" all the way to "received
      # confirmation email."
      change {Changes.GenerateOrderReference, []}
    end

    # Forward checkout transitions
    update :submit_contact_details do
      accept [:customer_name, :customer_email]
      require_attributes [:customer_name, :customer_email]
      change {Changes.UpsertUserAndAssignToCart, []}
      change transition_state(:gift_options)
      change load(@checkout_load)
      require_atomic? false
    end

    update :submit_gift_options do
      accept [:gift, :recipient_name, :card_message]
      change {Changes.TrimCardMessage, []}
      validate present(:recipient_name), where: [attribute_equals(:gift, true)]
      validate {Validations.ValidateCardMessageLength, []}
      change {Changes.ClearGiftFields, []}
      change transition_state(:delivery)
      change load(@checkout_load)
      require_atomic? false
    end

    update :submit_delivery do
      accept [
        :fulfillment_option_id,
        :recipient_name,
        :recipient_phone_number,
        :delivery_instructions,
        :fulfillment_date,
        :delivery_address
      ]

      change {Changes.CopyFulfillmentMethod, []}
      validate {Validations.ValidateFulfillmentDate, []}
      validate {Validations.ValidateDeliveryAddress, []}
      change {Changes.CalculateFulfillmentCost, []}
      change transition_state(:payment)
      change load(@checkout_load)
      require_atomic? false
    end

    # Backward "edit" transitions
    update :return_to_contact_details do
      change transition_state(:contact_details)
      change load(@checkout_load)
    end

    update :return_to_gift_options do
      change transition_state(:gift_options)
      change load(@checkout_load)
    end

    update :return_to_delivery do
      change transition_state(:delivery)
      change load(@checkout_load)
    end

    # Conversion: snapshots cart into a new Order + OrderLineItem rows, then
    # transitions the cart to :converted. Returns the cart; the caller can
    # read `cart.order_id` to find the freshly-created order.
    update :convert do
      validate present(:payment_intent_id)
      change {Changes.ConvertToOrder, []}
      change transition_state(:converted)
      change {Changes.UpdatePromotionUsageCount, []}
      require_atomic? false
    end

    update :update_fulfillment_option do
      accept [:fulfillment_option_id]
      change {Changes.CopyFulfillmentMethod, []}
      change set_attribute(:fulfillment_date, nil)
      change {Changes.ClearDeliveryFields, []}
      change load(@checkout_load)
      require_atomic? false
    end

    update :set_gift do
      accept [:gift]
      change load(@checkout_load)
    end

    update :update_locale do
      argument :locale, :string, allow_nil?: false
      validate argument_in(:locale, @locales)
      change atomic_update(:locale, expr(^arg(:locale)))
    end

    update :add_payment_intent_id do
      accept [:payment_intent_id]
    end

    update :mark_payment_failed do
      validate attribute_does_not_equal(:payment_status, :paid)
      change set_attribute(:payment_status, :failed)
    end

    update :add_promotion_with_id do
      argument :promotion_id, :uuid, allow_nil?: false
      validate {Validations.ValidateMinimumCartTotal, []}
      change atomic_update(:promotion_id, expr(^arg(:promotion_id)))
      change load(@checkout_load)
      require_atomic? false
    end

    update :add_promotion_with_code do
      argument :code, :string, allow_nil?: false, constraints: [trim?: true, min_length: 1]
      change {Changes.LookupPromotionCode, []}
      validate {Validations.ValidateMinimumCartTotal, []}
      change load(@checkout_load)
      require_atomic? false
    end

    update :clear_promotion do
      change atomic_update(:promotion_id, expr(nil))
      change load(@checkout_load)
    end

    update :restart_checkout do
      change {Changes.ResetCheckout, []}
      change transition_state(:contact_details)
      require_atomic? false
    end

    update :add_card do
      argument :product_variant_id, :uuid, allow_nil?: false
      change {Changes.SwapCardLineItem, []}
      change load(@checkout_load)
      require_atomic? false
    end

    update :remove_card do
      change set_attribute(:card_message, nil)
      change {Changes.RemoveCardLineItem, []}
      change load(@checkout_load)
      require_atomic? false
    end
  end

  policies do
    # System bypass - for webhooks and background jobs
    bypass actor_attribute_equals(:system, true) do
      authorize_if always()
    end

    # Admin bypass - admins can do anything
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Allow creating carts without authentication (for guest checkout)
    policy action_type(:create) do
      authorize_if always()
    end

    # Carts in checkout are public-by-id (the id is the session secret).
    # Converted carts are owner-only.
    policy action_type(:read) do
      authorize_if expr(state in ^@checkout_states)
      authorize_if expr(state == :converted and user_id == ^actor(:id))
    end

    # Only carts still in checkout are mutable. After conversion, the cart is
    # an audit record — the Order takes over.
    policy action_type(:update) do
      authorize_if expr(state in ^@checkout_states)
    end
  end

  attributes do
    uuid_primary_key :id

    # Generated at cart creation. Threaded through to Stripe metadata and
    # copied verbatim onto the Order at conversion time so the customer sees
    # one stable reference from "started checkout" through "confirmation
    # email."
    attribute :order_reference, :string, allow_nil?: false

    attribute :state, :atom do
      allow_nil? false
      default :contact_details
      constraints one_of: [:contact_details, :gift_options, :delivery, :payment, :converted]
    end

    # Tracks whether the latest payment attempt succeeded/failed. Conversion
    # only happens on payment success; this is for in-flight retry UX.
    attribute :payment_status, :atom,
      default: :pending,
      constraints: [
        one_of: [
          :pending,
          :paid,
          :failed
        ]
      ]

    # Step 1 - Your Details
    attribute :customer_name, :string
    attribute :customer_email, :string

    # Step 2 - Gift Options
    attribute :gift, :boolean, default: false
    attribute :card_message, :string

    # Step 3 - Delivery Information
    attribute :recipient_name, :string
    attribute :recipient_phone_number, :string
    attribute :delivery_address, :string
    attribute :delivery_instructions, :string
    attribute :fulfillment_date, :date
    attribute :fulfillment_amount, :decimal
    # Denormalized from fulfillment_option. Kept in sync by CopyFulfillmentMethod
    # so validations and templates can branch on a plain attribute instead of
    # traversing the relationship.
    attribute :fulfillment_method, FulfillmentOption.FulfillmentMethod
    attribute :geocoded_address, :string
    attribute :here_id, :string
    attribute :distance, :integer
    attribute :position, :string

    # Step 4 - Payment
    attribute :payment_intent_id, :string

    attribute :locale, :string, default: "sv-FI"

    timestamps()
  end

  relationships do
    belongs_to :user, Edenflowers.Accounts.User
    belongs_to :fulfillment_option, Edenflowers.Store.FulfillmentOption
    belongs_to :promotion, Edenflowers.Store.Promotion
    # Set when `:convert` succeeds. Lets the audit/refund flow walk
    # cart → order without an extra lookup by `order_reference`.
    belongs_to :order, Edenflowers.Store.Order
    has_many :line_items, Edenflowers.Store.CartLineItem
  end

  calculations do
    calculate :promotion_applied?, :boolean, expr(not is_nil(promotion_id))
    calculate :total, :decimal, expr(line_total + (fulfillment_amount || 0))

    calculate :fulfillment_tax_amount,
              :decimal,
              expr(
                if is_nil(fulfillment_option_id) do
                  0
                else
                  (fulfillment_amount || 0) * fulfillment_option.tax_rate.percentage
                end
              )

    calculate :tax_amount, :decimal, expr(line_tax_amount + fulfillment_tax_amount)

    # A cart with only a card line item is presented as empty in the UI
    # (card controls are hidden in the cart sidebar) and shouldn't keep
    # checkout alive on its own. Treat it as effectively empty so reset
    # logic and the mount guard agree with what the customer sees.
    calculate :cart_effectively_empty?, :boolean, expr(non_card_line_item_count == 0)
  end

  aggregates do
    sum :total_items_in_cart, :line_items, :quantity
    sum :line_total, :line_items, :line_total
    sum :line_tax_amount, :line_items, :line_tax_amount
    sum :discount_amount, :line_items, :discount_amount
    count :non_card_line_item_count, :line_items, filter: expr(is_card == false)
  end

  identities do
    identity :unique_order_reference, [:order_reference]
  end
end
