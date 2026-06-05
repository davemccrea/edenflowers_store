defmodule Edenflowers.Store.Order do
  use Ash.Resource,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshStateMachine]

  use GettextSigils, backend: EdenflowersWeb.Gettext

  require Ash.Resource.Change.Builtins

  alias __MODULE__.{Calculations, Changes, Validations}
  alias Edenflowers.Store.FulfillmentOption

  @locales Edenflowers.Locales.all()

  @checkout_load [
    :total_items_in_cart,
    :discount,
    :items_subtotal,
    :items_tax,
    :promotion_applied?,
    :grand_total,
    :tax,
    :fulfillment_tax,
    :cart_effectively_empty?,
    :promotion,
    :fulfillment_option,
    :line_items
  ]

  @admin_show_load [
    :customer_name,
    :grand_total,
    :items_subtotal,
    :items_tax,
    :tax,
    :fulfillment_tax,
    :discount,
    :distance_km,
    :promotion,
    :fulfillment_option,
    line_items: [:subtotal]
  ]

  postgres do
    repo Edenflowers.Repo
    table "orders"
  end

  @checkout_states [:contact_details, :gift_options, :delivery, :payment]

  def checkout_states, do: @checkout_states

  code_interface do
    define :create_for_checkout, action: :create_for_checkout
    define :get_by_id, action: :by_id, args: [:id]
    define :get_by_order_reference, action: :by_order_reference, args: [:order_reference]
    define :get_for_checkout, action: :for_checkout, args: [:id]
    define :get_for_admin, action: :admin_show, args: [:id]
    define :get_all_completed, action: :completed
    define :get_all_open, action: :open
    define :submit_contact_details, action: :submit_contact_details
    define :submit_gift_options, action: :submit_gift_options
    define :submit_delivery, action: :submit_delivery
    define :return_to_contact_details, action: :return_to_contact_details
    define :return_to_gift_options, action: :return_to_gift_options
    define :return_to_delivery, action: :return_to_delivery
    define :finalize_checkout, action: :finalize_checkout
    define :mark_payment_failed, action: :mark_payment_failed
    define :mark_fulfilled, action: :mark_fulfilled
    define :add_payment_intent_id, action: :add_payment_intent_id, args: [:payment_intent_id]
    define :mark_receipt_emailed, action: :mark_receipt_emailed, args: [:receipt_sha256]
    define :add_promotion_with_id, action: :add_promotion_with_id, args: [:promotion_id]
    define :add_promotion_with_code, action: :add_promotion_with_code, args: [:code]
    define :clear_promotion, action: :clear_promotion
    define :update_fulfillment_option, action: :update_fulfillment_option, args: [:fulfillment_option_id]
    define :set_gift, action: :set_gift, args: [:gift]
    define :update_locale, action: :update_locale, args: [:locale]
    define :restart_checkout, action: :restart_checkout
    define :add_card, action: :add_card, args: [:product_variant_id]
    define :remove_card, action: :remove_card
    define :remove_line_item, action: :remove_line_item, args: [:line_item_id]
    define :add_line_item, action: :add_line_item, args: [:product_variant_id, :quantity]
    define :increment_line_item, action: :increment_line_item, args: [:line_item_id]
    define :decrement_line_item, action: :decrement_line_item, args: [:line_item_id]
  end

  state_machine do
    initial_states([:contact_details])
    default_initial_state(:contact_details)

    transitions do
      transition(:submit_contact_details, from: :contact_details, to: :gift_options)
      transition(:submit_gift_options, from: :gift_options, to: :delivery)
      transition(:submit_delivery, from: :delivery, to: :payment)
      transition(:finalize_checkout, from: :payment, to: :placed)

      transition(:return_to_contact_details, from: [:gift_options, :delivery, :payment], to: :contact_details)
      transition(:return_to_gift_options, from: [:delivery, :payment], to: :gift_options)
      transition(:return_to_delivery, from: :payment, to: :delivery)

      transition(:restart_checkout, from: @checkout_states, to: :contact_details)
    end
  end

  actions do
    defaults [:read]

    # Read Actions
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

    read :for_checkout do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true
      prepare build(load: @checkout_load)
    end

    read :completed do
      filter expr(state == :placed)
    end

    read :open do
      filter expr(state == :placed and fulfillment_status == :pending)

      prepare build(
                sort: [fulfillment_date: :asc],
                load: [
                  :customer_name,
                  :order_reference,
                  :fulfillment_date,
                  :fulfillment_option_name,
                  :fulfillment_method,
                  :grand_total,
                  :non_card_line_item_count,
                  :distance_km,
                  :gift,
                  :recipient_name,
                  :card_message
                ]
              )
    end

    # Read-only table feed for the /admin/orders Cinder collection. Deliberately
    # separate from :open/:completed so table-shaped loads and sorting don't leak
    # into the dashboard/domain split.
    read :admin_list do
      pagination offset?: true, keyset?: true, countable: true, required?: false

      filter expr(state == :placed)

      prepare build(
                sort: [ordered_at: :desc],
                load: [
                  :customer_name,
                  :fulfillment_date,
                  :fulfillment_method,
                  :grand_total,
                  :payment_status,
                  :fulfillment_status
                ]
              )
    end

    read :admin_show do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id) and state == :placed)
      get? true
      prepare build(load: @admin_show_load)
    end

    # Create Actions
    create :create_for_checkout do
      change {Changes.GenerateOrderReference, []}
    end

    # Forward checkout transitions
    update :submit_contact_details do
      accept [:customer_name, :customer_email]
      require_attributes [:customer_name, :customer_email]

      argument :newsletter_opt_in, :boolean, default: false

      validate {Validations.ValidateCustomerEmail, []}
      change {Changes.UpsertUserAndAssignToOrder, []}
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

      change {Changes.SnapshotFulfillmentMethod, []}
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

    # Lifecycle transitions
    update :finalize_checkout do
      validate present(:payment_intent_id)
      change transition_state(:placed)
      change set_attribute(:payment_status, :paid)
      change set_attribute(:ordered_at, &DateTime.utc_now/0)
      change {Changes.UpdatePromotionUsageCount, []}
      require_atomic? false
    end

    update :update_fulfillment_option do
      accept [:fulfillment_option_id]
      change {Changes.SnapshotFulfillmentMethod, []}
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

    # require_atomic? false: AttributeEquals.atomic compiles `value != nil`
    # (always false in SQL); the non-atomic path uses is_nil/1 correctly.
    update :mark_receipt_emailed do
      argument :receipt_sha256, :string, allow_nil?: false

      validate attribute_equals(:receipt_emailed_at, nil),
        message: "receipt already marked as emailed"

      change set_attribute(:receipt_emailed_at, &DateTime.utc_now/0)
      change set_attribute(:receipt_sha256, arg(:receipt_sha256))
      require_atomic? false
    end

    update :mark_payment_failed do
      validate attribute_does_not_equal(:payment_status, :paid)
      change set_attribute(:payment_status, :failed)
    end

    update :mark_fulfilled do
      validate attribute_equals(:fulfillment_status, :pending)
      change set_attribute(:fulfillment_status, :fulfilled)
      change load(@admin_show_load)
    end

    update :add_promotion_with_id do
      argument :promotion_id, :uuid, allow_nil?: false
      validate {Validations.ValidateMinimumCartTotal, []}
      change atomic_update(:promotion_id, expr(^arg(:promotion_id)))
      change {Changes.SnapshotPromotion, []}
      change load(@checkout_load)
      require_atomic? false
    end

    update :add_promotion_with_code do
      argument :code, :string, allow_nil?: false, constraints: [trim?: true, min_length: 1]
      change {Changes.LookupPromotionCode, []}
      change {Changes.SnapshotPromotion, []}
      validate {Validations.ValidateMinimumCartTotal, []}
      change load(@checkout_load)
      require_atomic? false
    end

    update :clear_promotion do
      change atomic_update(:promotion_id, expr(nil))
      change {Changes.SnapshotPromotion, []}
      change load(@checkout_load)
      require_atomic? false
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

    update :remove_line_item do
      argument :line_item_id, :uuid, allow_nil?: false
      change {Changes.RemoveLineItem, []}
      change load(@checkout_load)
      require_atomic? false
    end

    update :add_line_item do
      argument :product_variant_id, :uuid, allow_nil?: false
      argument :quantity, :integer, allow_nil?: false, constraints: [min: 1]
      change {Changes.AddLineItem, []}
      change load(@checkout_load)
      require_atomic? false
    end

    update :increment_line_item do
      argument :line_item_id, :uuid, allow_nil?: false
      change {Changes.AdjustLineItemQuantity, direction: :increment}
      change load(@checkout_load)
      require_atomic? false
    end

    update :decrement_line_item do
      argument :line_item_id, :uuid, allow_nil?: false
      change {Changes.AdjustLineItemQuantity, direction: :decrement}
      change load(@checkout_load)
      require_atomic? false
    end
  end

  policies do
    # System bypass is scoped: anything outside this list (including updates
    # to a :placed order) falls through to the main policies.
    bypass actor_attribute_equals(:system, true) do
      authorize_if action([:finalize_checkout, :mark_payment_failed, :mark_receipt_emailed])
      authorize_if action_type(:read)
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if action(:mark_fulfilled)
      authorize_if action_type(:read)
    end

    # Guest checkout: creating an order does not require authentication.
    policy action_type(:create) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(state in ^@checkout_states)
      authorize_if expr(state == :placed and user_id == ^actor(:id))
    end

    # Placed orders are sealed for every actor, including admins and system.
    policy action_type(:update) do
      forbid_if expr(state == :placed)
      authorize_if expr(state in ^@checkout_states)
    end
  end

  pub_sub do
    module EdenflowersWeb.Endpoint

    publish :restart_checkout, ["order", "checkout_restarted", :id]
    publish :add_promotion_with_code, ["line_item", "changed", :id]
    publish :clear_promotion, ["line_item", "changed", :id]
  end

  attributes do
    uuid_primary_key :id

    attribute :order_reference, :string, allow_nil?: false

    attribute :state, :atom do
      allow_nil? false
      default :contact_details
      constraints one_of: [:contact_details, :gift_options, :delivery, :payment, :placed]
    end

    attribute :ordered_at, :utc_datetime

    attribute :payment_status, :atom,
      default: :pending,
      constraints: [
        one_of: [
          :pending,
          :paid,
          :failed,
          :refunded
        ]
      ]

    attribute :fulfillment_status, :atom,
      default: :pending,
      constraints: [
        one_of: [
          :pending,
          :fulfilled
        ]
      ]

    # Step 1 - Your Details
    attribute :customer_name, :string
    attribute :customer_email, :string

    # Stamped at submit time from the resolved user's subscription state so the
    # opt-in checkbox stays hidden when the customer returns to step 1 — the
    # checkout actor can't read another user's record to recompute it live.
    attribute :newsletter_offer_hidden?, :boolean, default: false, public?: false

    # Step 2 - Gift Options
    attribute :gift, :boolean, default: false
    attribute :card_message, :string

    # Step 3 - Delivery Information
    attribute :recipient_name, :string
    attribute :recipient_phone_number, :string
    attribute :delivery_address, :string
    attribute :delivery_instructions, :string
    attribute :fulfillment_date, :date
    attribute :fulfillment_fee, :decimal
    # Snapshotted from FulfillmentOption (+ its TaxRate) by
    # SnapshotFulfillmentMethod. Frozen once the order is placed.
    attribute :fulfillment_method, FulfillmentOption.FulfillmentMethod
    attribute :fulfillment_tax_percentage, :decimal
    attribute :fulfillment_option_name, :string
    attribute :geocoded_address, :string
    attribute :here_id, :string
    attribute :distance, :integer
    attribute :position, :string

    # Step 4 - Payment
    attribute :payment_intent_id, :string

    # Snapshotted from Promotion by SnapshotPromotion. Frozen once the order
    # is placed.
    attribute :discount_rate, :decimal
    attribute :promotion_name, :string
    attribute :promotion_code, :string

    attribute :locale, :string, default: "sv-FI"

    # The SHA proves what was sent without persisting the PDF — the renderer is deterministic
    # over the placed order's snapshot columns, so a re-render should reproduce these bytes.
    attribute :receipt_emailed_at, :utc_datetime
    attribute :receipt_sha256, :string

    timestamps()
  end

  relationships do
    belongs_to :user, Edenflowers.Accounts.User
    belongs_to :fulfillment_option, Edenflowers.Store.FulfillmentOption
    belongs_to :promotion, Edenflowers.Store.Promotion
    has_many :line_items, Edenflowers.Store.LineItem
  end

  calculations do
    calculate :customer_first_name, :string, {Edenflowers.Accounts.Calculations.FirstName, source: :customer_name}

    # `distance` is snapshotted in metres; expose it as a kilometre string for
    # display, and only for deliveries.
    calculate :distance_km, :string, Calculations.DistanceKm

    calculate :promotion_applied?, :boolean, expr(not is_nil(promotion_id))
    calculate :grand_total, :decimal, expr(items_subtotal + (fulfillment_fee || 0))

    calculate :fulfillment_tax,
              :decimal,
              expr((fulfillment_fee || 0) * (fulfillment_tax_percentage || 0))

    calculate :tax, :decimal, expr(items_tax + fulfillment_tax)

    # A cart with only a card line item is presented as empty in the UI
    # (card controls are hidden in the cart sidebar) and shouldn't keep
    # checkout alive on its own. Treat it as effectively empty so reset
    # logic and the mount guard agree with what the customer sees.
    calculate :cart_effectively_empty?, :boolean, expr(non_card_line_item_count == 0)
  end

  aggregates do
    sum :total_items_in_cart, :line_items, :quantity
    sum :items_subtotal, :line_items, :total
    sum :items_tax, :line_items, :tax
    sum :discount, :line_items, :discount
    count :non_card_line_item_count, :line_items, filter: expr(is_card == false)
  end

  identities do
    identity :unique_order_reference, [:order_reference]
  end
end
