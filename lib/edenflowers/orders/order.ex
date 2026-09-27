defmodule Edenflowers.Orders.Order.PaymentStatus do
  use Ash.Type.Enum, values: [:pending, :paid, :failed, :refunded]
end

defmodule Edenflowers.Orders.Order.FulfillmentStatus do
  use Ash.Type.Enum, values: [:pending, :fulfilled]
end

defmodule Edenflowers.Orders.Order do
  use Ash.Resource,
    domain: Edenflowers.Orders,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshStateMachine, AshOban]

  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias __MODULE__.{Actions, Calculations, Changes, Validations}
  alias Edenflowers.Fulfillment.FulfillmentOption

  @locales Edenflowers.Locales.all()

  @checkout_load [
    :recipient_first_name,
    :total_items_in_cart,
    :discount,
    :items_subtotal,
    :items_total,
    :promotion_applied?,
    :grand_total,
    :vat,
    :cart_effectively_empty?,
    :newsletter_offer_hidden?,
    :promotion,
    :fulfillment_option,
    line_items: [:total]
  ]

  @admin_show_load [
    :customer_name,
    :customer_first_name,
    :grand_total,
    :amount_mismatch?,
    :items_subtotal,
    :items_total,
    :vat,
    :discount,
    :distance_km,
    :promotion,
    :fulfillment_option,
    line_items: [:subtotal, :total]
  ]

  postgres do
    repo Edenflowers.Repo
    table "orders"
    migration_types fulfillment_fee: :decimal, amount_paid: :decimal

    check_constraints do
      check_constraint :fulfillment_fee, "orders_valid_fulfillment_fee",
        check: "fulfillment_fee >= 0 AND fulfillment_fee = round(fulfillment_fee, 2)",
        message: "must be a non-negative amount in whole cents"

      check_constraint :amount_paid, "orders_valid_amount_paid",
        check: "amount_paid >= 0 AND amount_paid = round(amount_paid, 2)",
        message: "must be a non-negative amount in whole cents"

      check_constraint :amount_paid, "orders_paid_requires_amount",
        check: "payment_status != 'paid' OR amount_paid IS NOT NULL",
        message: "must be present when payment is paid"
    end
  end

  @checkout_states [:contact_details, :gift_options, :delivery, :payment]

  def checkout_states, do: @checkout_states

  state_machine do
    initial_states([:contact_details])
    default_initial_state(:contact_details)

    transitions do
      transition(:submit_contact_details, from: :contact_details, to: :gift_options)
      transition(:submit_gift_options, from: :gift_options, to: :delivery)
      transition(:submit_delivery, from: :delivery, to: :payment)
      # The customer has paid, so any step they have since stepped back to still places the order.
      transition(:finalize_checkout, from: @checkout_states, to: :placed)

      transition(:return_to_contact_details, from: [:gift_options, :delivery, :payment], to: :contact_details)
      transition(:return_to_gift_options, from: [:delivery, :payment], to: :gift_options)
      transition(:return_to_delivery, from: :payment, to: :delivery)

      transition(:restart_checkout, from: @checkout_states, to: :contact_details)
    end
  end

  oban do
    triggers do
      trigger :send_confirmation_email do
        action :send_confirmation_email
        queue :default
        max_attempts 20
        lock_for_update? false
        scheduler_cron "*/10 * * * *"
        worker_module_name Edenflowers.Orders.Order.Workers.SendConfirmationEmail
        scheduler_module_name Edenflowers.Orders.Order.Schedulers.SendConfirmationEmail
        default_actor Edenflowers.Actors.system_actor()
        where expr(state == :placed and payment_status == :paid and is_nil(receipt_emailed_at))
      end

      trigger :reconcile_payment do
        action :reconcile_payment
        queue :default
        max_attempts 1
        lock_for_update? false
        scheduler_cron "*/10 * * * *"
        worker_module_name Edenflowers.Orders.Order.Workers.ReconcilePayment
        scheduler_module_name Edenflowers.Orders.Order.Schedulers.ReconcilePayment
        default_actor Edenflowers.Actors.system_actor()

        where expr(
                state != :placed and not is_nil(payment_intent_id) and
                  updated_at < ago(5, :minute) and updated_at > ago(7, :day)
              )
      end

      # InitStore opens a cart for every new browser session, crawlers included.
      trigger :purge_abandoned_cart do
        action :purge_abandoned_cart
        queue :default
        max_attempts 1
        lock_for_update? false
        scheduler_cron "0 3 * * *"
        worker_module_name Edenflowers.Orders.Order.Workers.PurgeAbandonedCart
        scheduler_module_name Edenflowers.Orders.Order.Schedulers.PurgeAbandonedCart
        default_actor Edenflowers.Actors.system_actor()

        where expr(
                state != :placed and is_nil(payment_intent_id) and not exists(line_items, true) and
                  updated_at < ago(1, :day)
              )
      end
    end
  end

  actions do
    defaults [:read]

    destroy :purge_abandoned_cart

    read :for_checkout do
      prepare build(load: @checkout_load)
    end

    # Scoped to the actor by filter, not by policy: the admin bypass above grants
    # admins an unrestricted read, so an action named for the customer's own
    # order history has to narrow itself or it hands Jennie everyone's orders.
    read :mine do
      filter expr(state == :placed and user_id == ^actor(:id))

      prepare build(sort: [ordered_at: :desc, inserted_at: :desc], load: [:grand_total])
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
                  :card_message,
                  :line_items
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
                  :amount_mismatch?,
                  :payment_status,
                  :fulfillment_status
                ]
              )
    end

    read :to_fulfil do
      filter expr(state == :placed and payment_status == :paid and fulfillment_status == :pending)
      prepare build(sort: [fulfillment_date: :asc, ordered_at: :asc, id: :asc])
    end

    read :admin_show do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id) and state == :placed)
      get? true
      prepare build(load: @admin_show_load)
    end

    create :create_for_checkout

    # Forward checkout transitions
    update :submit_contact_details do
      accept [:customer_name, :customer_email]
      require_attributes [:customer_name, :customer_email]

      argument :newsletter_opt_in, :boolean, default: false

      validate match(:customer_email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/), message: "Must be a valid email address"
      change Changes.UpsertUserAndAssignToOrder
      change transition_state(:gift_options)
      require_atomic? false
    end

    update :submit_gift_options do
      accept [:gift, :recipient_name, :card_message]
      validate present(:recipient_name), where: [attribute_equals(:gift, true)]
      validate Validations.ValidateCardMessageLength
      change set_attribute(:recipient_name, nil), where: attribute_equals(:gift, false)
      change set_attribute(:card_message, nil), where: attribute_equals(:gift, false)
      change Changes.RemoveCardLineItem, where: attribute_equals(:gift, false)
      change transition_state(:delivery)
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

      change Changes.SnapshotFulfillmentMethod
      validate present(:fulfillment_date)
      validate Validations.ValidateFulfillmentDate
      validate Validations.ValidateDeliveryAddress
      validate present(:recipient_phone_number)
      change Changes.NormalizePhoneNumber
      change Changes.CalculateFulfillmentCost
      change transition_state(:payment)
      require_atomic? false
    end

    # Backward "edit" transitions
    update :return_to_contact_details do
      change transition_state(:contact_details)
    end

    update :return_to_gift_options do
      change transition_state(:gift_options)
    end

    update :return_to_delivery do
      change transition_state(:delivery)
    end

    # Lifecycle transitions
    update :finalize_checkout do
      argument :payment_intent_id, :string, allow_nil?: false
      argument :amount_paid, :decimal, allow_nil?: false, constraints: [min: 0, scale: 2]
      validate {Edenflowers.Payments.Validations.NotAlreadyPaid, attribute: :payment_status, paid: :paid}
      validate Edenflowers.Payments.Validations.MatchesPaymentIntent
      change set_attribute(:amount_paid, arg(:amount_paid))

      # The atomic condition also keeps streamed updates from rejecting a
      # redelivery in memory before the database can return AlreadyPaid.
      change transition_state(:placed),
        always_atomic?: true,
        where: [{Edenflowers.Payments.Validations.NotAlreadyPaid, attribute: :payment_status, paid: :paid}]

      change set_attribute(:payment_status, :paid)
      change set_attribute(:ordered_at, &DateTime.utc_now/0)
      change Changes.GenerateOrderReference
      change Changes.SnapshotVatBreakdown
      change Changes.ReportAmountMismatch
      change Changes.ReportPromotionOverused

      change Edenflowers.Payments.Changes.ScheduleConfirmationEmail

      require_atomic? false
    end

    update :update_fulfillment_option do
      accept [:fulfillment_option_id]
      change Changes.SnapshotFulfillmentMethod
      change set_attribute(:fulfillment_date, nil)
      change Changes.ClearDeliveryFields
      require_atomic? false
    end

    update :set_gift do
      accept [:gift]
    end

    update :update_locale do
      accept [:locale]
      validate attribute_in(:locale, @locales)
    end

    update :add_payment_intent_id do
      accept [:payment_intent_id]
      validate Edenflowers.Payments.Validations.PaymentIntentNotSet
    end

    update :send_confirmation_email do
      accept []
      transaction? false
      require_atomic? false
      change Changes.SendConfirmationEmail
    end

    update :reconcile_payment do
      accept []
      transaction? false
      require_atomic? false
      change Edenflowers.Payments.Changes.Reconcile
    end

    # A succeeded event may have arrived first, or been reprocessed. Don't downgrade.
    update :mark_payment_failed do
      argument :payment_intent_id, :string, allow_nil?: false
      validate {Edenflowers.Payments.Validations.NotAlreadyPaid, attribute: :payment_status, paid: :paid}
      validate Edenflowers.Payments.Validations.MatchesPaymentIntent
      change set_attribute(:payment_status, :failed)
    end

    action :sales_summary, :map do
      description "Counts paid orders and sums their totals between two dates, inclusive, in Helsinki time."

      constraints fields: [
                    order_count: [type: :integer, allow_nil?: false],
                    revenue: [type: :decimal, allow_nil?: false, constraints: [min: 0, scale: 2]]
                  ]

      argument :from, :date, allow_nil?: false
      argument :to, :date, allow_nil?: false

      run Actions.SalesSummary
    end

    update :mark_fulfilled do
      validate attribute_equals(:fulfillment_status, :pending)
      change set_attribute(:fulfillment_status, :fulfilled)
      change load(@admin_show_load)
    end

    update :add_promotion_with_code do
      argument :code, :string, allow_nil?: false, constraints: [trim?: true, min_length: 1]
      change Changes.ApplyPromotion
      require_atomic? false
    end

    update :clear_promotion do
      change set_attribute(:promotion_id, nil)
      change set_attribute(:discount_rate, nil)
      change set_attribute(:promotion_name, nil)
      change set_attribute(:promotion_code, nil)
      change set_attribute(:promotion_minimum_cart_total, nil)
    end

    update :restart_checkout do
      change Changes.ResetCheckout
      change transition_state(:contact_details)
      require_atomic? false
    end

    update :add_card do
      argument :product_variant_id, :uuid, allow_nil?: false
      change Changes.SwapCardLineItem
      require_atomic? false
    end

    update :remove_card do
      change set_attribute(:card_message, nil)
      change Changes.RemoveCardLineItem
      require_atomic? false
    end

    update :remove_line_item do
      argument :line_item_id, :uuid, allow_nil?: false
      change Changes.RemoveLineItem
      require_atomic? false
    end
  end

  policies do
    # System bypass is scoped: anything outside this list (including updates
    # to a :placed order) falls through to the main policies.
    bypass actor_attribute_equals(:system, true) do
      authorize_if action([
                     :finalize_checkout,
                     :mark_payment_failed,
                     :send_confirmation_email,
                     :reconcile_payment,
                     :purge_abandoned_cart
                   ])

      authorize_if action_type(:read)
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if action([:mark_fulfilled, :sales_summary])
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
    publish :finalize_checkout, ["order", "placed", :id]
    publish :add_promotion_with_code, ["line_item", "changed", :id]
    publish :clear_promotion, ["line_item", "changed", :id]
  end

  attributes do
    uuid_primary_key :id

    attribute :order_reference, :string

    attribute :ordered_at, :utc_datetime

    attribute :payment_status, __MODULE__.PaymentStatus, default: :pending
    attribute :fulfillment_status, __MODULE__.FulfillmentStatus, default: :pending

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
    attribute :fulfillment_fee, :decimal, constraints: [min: 0, scale: 2]
    # Snapshotted from FulfillmentOption (+ its TaxRate) by
    # SnapshotFulfillmentMethod. Frozen once the order is placed.
    attribute :fulfillment_method, FulfillmentOption.FulfillmentMethod
    attribute :fulfillment_tax_rate, :decimal
    attribute :fulfillment_option_name, :string
    attribute :geocoded_address, :string
    attribute :here_id, :string
    attribute :distance, :integer
    attribute :position, :string

    # Step 4 - Payment
    attribute :payment_intent_id, :string
    # What Stripe actually charged. Differs from grand_total when the cart
    # changed while payment was in flight.
    attribute :amount_paid, :decimal, constraints: [min: 0, scale: 2]

    # Snapshotted from Promotion by ApplyPromotion. Frozen once the order
    # is placed.
    attribute :discount_rate, :decimal
    attribute :promotion_name, :string
    attribute :promotion_code, :string
    attribute :promotion_minimum_cart_total, :decimal

    attribute :locale, :string, default: "sv-FI"

    # The SHA proves what was sent without persisting the PDF — the renderer is deterministic
    # over the placed order's snapshot columns, so a re-render should reproduce these bytes.
    attribute :receipt_emailed_at, :utc_datetime
    attribute :receipt_sha256, :string
    attribute :vat_breakdown, {:array, Edenflowers.Orders.VatRow}

    timestamps()
  end

  relationships do
    belongs_to :user, Edenflowers.Accounts.User
    belongs_to :fulfillment_option, Edenflowers.Fulfillment.FulfillmentOption
    belongs_to :promotion, Edenflowers.Pricing.Promotion
    has_many :line_items, Edenflowers.Orders.LineItem
  end

  calculations do
    calculate :customer_first_name, :string, {Edenflowers.Accounts.Calculations.FirstName, source: :customer_name}
    calculate :recipient_first_name, :string, {Edenflowers.Accounts.Calculations.FirstName, source: :recipient_name}

    # `distance` is snapshotted in metres; expose it as a kilometre string for
    # display, and only for deliveries.
    calculate :distance_km, :string, Calculations.DistanceKm

    # A code stays on the order when the cart drops below its minimum, but
    # only discounts while the cart meets it.
    calculate :promotion_applied?,
              :boolean,
              expr(
                if(
                  not is_nil(promotion_id) and
                    (is_nil(promotion_minimum_cart_total) or items_subtotal >= promotion_minimum_cart_total),
                  true,
                  false
                )
              )

    calculate :grand_total, :decimal, expr(items_total + (fulfillment_fee || 0))
    calculate :amount_mismatch?, :boolean, expr(not is_nil(amount_paid) and amount_paid != grand_total)

    calculate :vat, :decimal, Calculations.Vat

    # False until step 1 assigns the customer.
    calculate :newsletter_offer_hidden?, :boolean, expr(if(customer_newsletter_offer_hidden?, true, false))

    # A cart with only a card line item is presented as empty in the UI
    # (card controls are hidden in the cart sidebar) and shouldn't keep
    # checkout alive on its own. Treat it as effectively empty so reset
    # logic and the mount guard agree with what the customer sees.
    calculate :cart_effectively_empty?, :boolean, expr(non_card_line_item_count == 0)
  end

  aggregates do
    sum :total_items_in_cart, :line_items, :quantity, default: 0
    sum :items_subtotal, :line_items, :subtotal, default: Decimal.new("0")
    sum :items_total, :line_items, :total, default: Decimal.new("0")
    sum :discount, :line_items, :discount, default: Decimal.new("0")
    count :non_card_line_item_count, :line_items, filter: expr(is_card == false)

    # Unauthorized because the checkout actor, often a guest, can't read the
    # order's user under the User read policy.
    first :customer_newsletter_offer_hidden?, :user, :newsletter_offer_hidden? do
      authorize? false
    end
  end

  identities do
    identity :unique_order_reference, [:order_reference]
  end
end
