defmodule Edenflowers.Orders.Order.PaymentStatus do
  use Ash.Type.Enum, values: [:pending, :paid, :failed, :refunded]
end

defmodule Edenflowers.Orders.Order.FulfillmentStatus do
  use Ash.Type.Enum, values: [:pending, :fulfilled, :cancelled]
end

defmodule Edenflowers.Orders.Order.Origin do
  @moduledoc "An online order comes through checkout; a custom order is entered by Jennie in the admin."
  use Ash.Type.Enum, values: [:online, :custom]
end

defmodule Edenflowers.Orders.Order.PaymentMethod do
  @moduledoc """
  How a paid order was paid. `:stripe` covers checkout and the payment link,
  card or MobilePay alike. The rest are in-person payments Jennie records herself;
  `:mobilepay` is her own MobilePay number, outside Stripe.
  """
  use Ash.Type.Enum, values: [:stripe, :zettle, :mobilepay, :cash]

  def in_person, do: [:zettle, :mobilepay, :cash]
end

defmodule Edenflowers.Orders.Order do
  use Ash.Resource,
    domain: Edenflowers.Orders,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshStateMachine, AshOban, AshPaperTrail.Resource]

  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Orders.{Actions, Calculations, Changes, Validations}
  alias Edenflowers.Fulfillment.FulfillmentOption
  alias __MODULE__.PaymentMethod

  @locales Edenflowers.Locales.all()

  @custom_order_fields [
    :locale,
    :customer_name,
    :customer_email,
    :customer_phone_number,
    :recipient_name,
    :recipient_phone_number,
    :card_message,
    :fulfillment_option_id,
    :fulfillment_date,
    :delivery_address,
    :delivery_instructions,
    :fulfillment_fee_override,
    :florist_note
  ]

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
    :amount_paid,
    :balance,
    :unpaid?,
    :payment_link_open?,
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
    migration_types fulfillment_fee: :decimal, fulfillment_fee_override: :decimal

    check_constraints do
      check_constraint :fulfillment_fee, "orders_valid_fulfillment_fee",
        check: "fulfillment_fee >= 0 AND fulfillment_fee = round(fulfillment_fee, 2)",
        message: "must be a non-negative amount in whole cents"
    end

    # Shared with course registrations so an order and a booking never have
    # the same number.
    custom_statements do
      statement :reference_seq do
        up "CREATE SEQUENCE reference_seq START 1400"
        down "DROP SEQUENCE reference_seq"
      end
    end
  end

  @checkout_states [:contact_details, :gift_options, :delivery, :payment]

  def checkout_states, do: @checkout_states

  state_machine do
    # A custom order skips checkout: Jennie creates it already placed.
    initial_states([:contact_details, :placed])
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
        worker_module_name Edenflowers.Orders.Workers.SendConfirmationEmail
        scheduler_module_name Edenflowers.Orders.Schedulers.SendConfirmationEmail
        default_actor Edenflowers.Actors.system_actor()
        # An in-person payment gets its receipt only when Jennie sends one.
        where expr(
                state == :placed and exists(payments, method == :stripe) and not is_nil(customer_email) and
                  is_nil(receipt_emailed_at)
              )
      end

      # Queued only when Jennie places a custom order and ticks "email the customer",
      # so there is no schedule to pick up the ones she chose not to send.
      trigger :send_order_details_email do
        action :send_order_details_email
        queue :default
        max_attempts 20
        lock_for_update? false
        scheduler_cron false
        worker_module_name Edenflowers.Orders.Workers.SendOrderDetailsEmail
        scheduler_module_name Edenflowers.Orders.Schedulers.SendOrderDetailsEmail
        default_actor Edenflowers.Actors.system_actor()
        where expr(origin == :custom and not is_nil(customer_email) and is_nil(details_emailed_at))
      end

      trigger :send_delivered_email do
        action :send_delivered_email
        queue :default
        max_attempts 20
        lock_for_update? false
        scheduler_cron "*/10 * * * *"
        worker_module_name Edenflowers.Orders.Workers.SendDeliveredEmail
        scheduler_module_name Edenflowers.Orders.Schedulers.SendDeliveredEmail
        default_actor Edenflowers.Actors.system_actor()

        where expr(
                state == :placed and fulfillment_method == :delivery and fulfillment_status == :fulfilled and
                  not is_nil(customer_email) and is_nil(delivered_emailed_at)
              )
      end

      trigger :reconcile_payment do
        action :reconcile_payment
        queue :default
        max_attempts 1
        lock_for_update? false
        scheduler_cron "*/10 * * * *"
        worker_module_name Edenflowers.Orders.Workers.ReconcilePayment
        scheduler_module_name Edenflowers.Orders.Schedulers.ReconcilePayment
        default_actor Edenflowers.Actors.system_actor()

        # payment_intent_id is only set while a PaymentIntent waits for the
        # customer, at checkout or on a payment link.
        where expr(
                not is_nil(payment_intent_id) and fulfillment_status != :cancelled and
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
        worker_module_name Edenflowers.Orders.Workers.PurgeAbandonedCart
        scheduler_module_name Edenflowers.Orders.Schedulers.PurgeAbandonedCart
        default_actor Edenflowers.Actors.system_actor()

        where expr(
                state != :placed and is_nil(payment_intent_id) and not exists(line_items, true) and
                  updated_at < ago(1, :day)
              )
      end
    end
  end

  # The order log on the admin order page. Only what happens to an order once
  # it is placed: checkout's cart steps would bury it, and crawlers' carts with it.
  paper_trail do
    # full_diff would show "from → to", but it can't track atomic updates,
    # and checkout's payment guards depend on being atomic.
    change_tracking_mode :changes_only
    # The only destroy purges abandoned carts, which have no log.
    create_version_on_destroy? false
    # An edit that changes only the lines changes nothing on the order row, but
    # still belongs in the log. ReplaceLineItems asks to skip an edit that
    # changed nothing at all.
    only_when_changed? false
    store_action_name? true
    ignore_attributes [:inserted_at, :updated_at]
    sensitive_attributes :redact

    # Set by ReplaceLineItems when the lines change: what they now are,
    # since changes_only can't see into another resource.
    metadata :items, :string

    on_actions [
      :finalize_checkout,
      :place_custom,
      :edit,
      :update_florist_note,
      :cancel,
      :mark_fulfilled,
      :open_payment_link,
      :send_order_details_email,
      :send_confirmation_email,
      :send_delivered_email,
      :email_receipt
    ]
  end

  actions do
    defaults [:read]

    destroy :purge_abandoned_cart

    read :for_checkout do
      prepare build(load: @checkout_load)
    end

    # Scoped to the actor by filter, not by policy: the admin bypass in policies grants
    # admins an unrestricted read, so an action named for the customer's own
    # order history has to narrow itself or it hands Jennie everyone's orders.
    read :mine do
      filter expr(state == :placed and user_id == ^actor(:id))

      prepare build(sort: [ordered_at: :desc, inserted_at: :desc], load: [:grand_total, :payment_link_open?])
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
                  :balance,
                  :payment_status,
                  :fulfillment_status
                ]
              )
    end

    read :to_fulfil do
      # Unpaid custom orders still have to be made (ADR 0001).
      filter expr(state == :placed and fulfillment_status == :pending)
      prepare build(sort: [fulfillment_date: :asc, ordered_at: :asc, id: :asc])
    end

    read :admin_show do
      filter expr(state == :placed)
      prepare build(load: @admin_show_load)
    end

    read :by_payment_link_token do
      argument :token, :string, allow_nil?: false
      get? true
      filter expr(state == :placed and not is_nil(payment_link_token) and payment_link_token == ^arg(:token))
      prepare build(load: [:grand_total, :amount_paid, :balance, :items_total, :vat, line_items: [:subtotal]])
    end

    create :create_for_checkout

    create :place_custom do
      accept @custom_order_fields

      argument :line_items, {:array, :map}, allow_nil?: false
      argument :payment_link?, :boolean, default: true
      argument :email_customer?, :boolean, default: true

      change set_attribute(:state, :placed)
      change set_attribute(:origin, :custom)
      change set_attribute(:ordered_at, &DateTime.utc_now/0)
      change atomic_set(:order_reference, expr(fragment("nextval('reference_seq')::text")))
      change Changes.OpenPaymentLink, where: [argument_equals(:payment_link?, true)]

      validate Validations.EnteredLineItems
      validate attribute_in(:locale, @locales)
      validate present(:customer_name)

      validate present([:customer_email, :customer_phone_number], at_least: 1),
        message: "enter a phone number or an email"

      validate match(:customer_email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/), message: "Must be a valid email address"
      change Changes.SnapshotFulfillmentMethod
      validate present(:fulfillment_option_id)
      validate present(:fulfillment_date)
      validate Validations.FulfillmentDateNotPast
      validate Validations.DeliveryAddress
      validate present(:recipient_phone_number), where: [attribute_equals(:fulfillment_method, :delivery)]
      validate Validations.CardMessageLength
      change {Changes.NormalizePhoneNumber, attribute: :customer_phone_number}
      change Changes.NormalizePhoneNumber
      change Changes.SetGiftFromRecipient
      change Changes.PriceFulfillment
      change Changes.UpsertUserAndAssignToOrder, where: [present(:customer_email)]
      change Changes.ReplaceLineItems
      change run_oban_trigger(:send_order_details_email), where: [argument_equals(:email_customer?, true)]
    end

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
      validate Validations.CardMessageLength
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
      validate Validations.FulfillmentDate
      validate Validations.DeliveryAddress
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

      # The atomic condition also keeps streamed updates from rejecting a
      # redelivery in memory before the database can return AlreadyPaid.
      change transition_state(:placed),
        always_atomic?: true,
        where: [{Edenflowers.Payments.Validations.NotAlreadyPaid, attribute: :payment_status, paid: :paid}]

      change set_attribute(:payment_status, :paid)
      change set_attribute(:ordered_at, &DateTime.utc_now/0)
      change atomic_set(:order_reference, expr(fragment("nextval('reference_seq')::text")))
      change Changes.SnapshotVatBreakdown
      change {Changes.RecordPayment, method: :stripe, amount: :amount_paid}
      change Changes.ReportAmountMismatch
      change Changes.ReportPromotionOverused

      change Edenflowers.Payments.Changes.ScheduleConfirmationEmail

      require_atomic? false
    end

    # Jennie can change anything on an open order, online or custom, paid or
    # not. A paid order whose total changes is left with a balance to collect
    # or refund; an unpaid one's payment link charges the new total.
    update :edit do
      accept @custom_order_fields

      argument :line_items, {:array, :map}, allow_nil?: false

      validate attribute_equals(:fulfillment_status, :pending), message: "is no longer open"

      validate Validations.EnteredLineItems
      validate attribute_in(:locale, @locales)
      validate present(:customer_name)

      validate present([:customer_email, :customer_phone_number], at_least: 1),
        message: "enter a phone number or an email"

      validate match(:customer_email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/), message: "Must be a valid email address"
      change Changes.SnapshotFulfillmentMethod
      validate present(:fulfillment_option_id)
      validate present(:fulfillment_date)
      validate Validations.FulfillmentDateNotPast
      validate Validations.DeliveryAddress
      validate present(:recipient_phone_number), where: [attribute_equals(:fulfillment_method, :delivery)]
      validate Validations.CardMessageLength
      change {Changes.NormalizePhoneNumber, attribute: :customer_phone_number}
      change Changes.NormalizePhoneNumber
      change Changes.SetGiftFromRecipient
      change Changes.PriceFulfillment
      change Changes.UpsertUserAndAssignToOrder, where: [present(:customer_email), changing(:customer_email)]
      change Changes.ReplaceLineItems
      require_atomic? false
    end

    update :update_florist_note do
      accept [:florist_note]
      change set_context(%{skip_version_when_unchanged?: true})
    end

    # Never refunds: Jennie refunds a paid order in the Stripe dashboard.
    update :cancel do
      validate attribute_equals(:fulfillment_status, :pending), message: "is no longer open"
      change set_attribute(:fulfillment_status, :cancelled)
      change set_attribute(:cancelled_at, &DateTime.utc_now/0)
      change Changes.CancelOpenPaymentIntent
      change load(@admin_show_load)
      require_atomic? false
    end

    # Money Jennie takes in person, or hands back as a negative amount. Any
    # amount goes, so she can also settle a balance left by an edit.
    update :record_in_person_payment do
      argument :amount, :decimal, allow_nil?: false, constraints: [scale: 2]
      argument :payment_method, PaymentMethod, allow_nil?: false

      validate argument_in(:payment_method, PaymentMethod.in_person())
      validate attribute_does_not_equal(:fulfillment_status, :cancelled), message: "is cancelled"
      change set_attribute(:payment_status, :paid)
      # The link charges the balance, which this payment changes; visiting it
      # again opens a PaymentIntent for whatever is left.
      change Changes.CancelOpenPaymentIntent
      change {Changes.RecordPayment, amount: :amount}
      change load(@admin_show_load)
      require_atomic? false
    end

    # A payment through the payment link: a custom order's first payment, or
    # a balance left by editing any order. The order is already placed, so
    # unlike finalize_checkout this only records the payment.
    update :record_link_payment do
      argument :payment_intent_id, :string, allow_nil?: false
      argument :amount_paid, :decimal, allow_nil?: false, constraints: [min: 0, scale: 2]
      # No check that this is the order's current PaymentIntent: one Jennie
      # dropped can still be paid, and that money has arrived all the same.
      # Only the PaymentIntent that was paid stops being open.
      change fn changeset, _context ->
        if changeset.data.payment_intent_id == Ash.Changeset.get_argument(changeset, :payment_intent_id),
          do: Ash.Changeset.force_change_attribute(changeset, :payment_intent_id, nil),
          else: changeset
      end

      change set_attribute(:payment_status, :paid)
      # The receipt goes out again, showing the order as it now stands.
      change set_attribute(:receipt_emailed_at, nil)
      change {Changes.RecordPayment, method: :stripe, amount: :amount_paid}
      change Changes.ReportUnexpectedPayment
      change Edenflowers.Payments.Changes.ScheduleConfirmationEmail
      require_atomic? false
    end

    # Recorded from Stripe's refund webhook, so a refund Jennie makes in the
    # Stripe dashboard shows up on the order without her entering it again.
    update :record_stripe_refund do
      argument :stripe_refund_id, :string, allow_nil?: false
      argument :amount, :decimal, allow_nil?: false, constraints: [max: 0, scale: 2]
      change {Changes.RecordPayment, method: :stripe, amount: :amount}
      require_atomic? false
    end

    # Any order owing money can have a link: a custom order paid later, or an
    # order edited after it was paid.
    update :open_payment_link do
      validate attribute_does_not_equal(:fulfillment_status, :cancelled), message: "is cancelled"
      change set_context(%{skip_version_when_unchanged?: true})
      change Changes.OpenPaymentLink
      change load(@admin_show_load)
      require_atomic? false
    end

    update :send_order_details_email do
      accept []
      transaction? false
      require_atomic? false
      change Changes.SendOrderDetailsEmail
    end

    # For an in-person payment, whose receipt is only sent when the customer asks.
    update :email_receipt do
      accept []
      validate attribute_equals(:payment_status, :paid), message: "is not paid yet"
      validate present(:customer_email), message: "has no email address"
      transaction? false
      require_atomic? false
      change Changes.SendConfirmationEmail
    end

    update :refresh_vat_breakdown do
      accept []
      change Changes.SnapshotVatBreakdown
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

    update :send_delivered_email do
      accept []
      transaction? false
      require_atomic? false
      change Changes.SendDeliveredEmail
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
      # A placed custom order still waits for its money after a declined card, and
      # cancelling one cancels its PaymentIntent too; neither is a failed checkout.
      change set_attribute(:payment_status, :failed), where: [attribute_does_not_equal(:state, :placed)]
    end

    action :sales_summary, :map do
      description "Counts paid orders placed between two dates, inclusive, in Helsinki time, and sums the money " <>
                    "received in that range, refunds taken off."

      constraints fields: [
                    order_count: [type: :integer, allow_nil?: false],
                    revenue: [type: :decimal, allow_nil?: false, constraints: [scale: 2]]
                  ]

      argument :from, :date, allow_nil?: false
      argument :to, :date, allow_nil?: false

      run Actions.SalesSummary
    end

    update :mark_fulfilled do
      validate attribute_equals(:fulfillment_status, :pending)
      change set_attribute(:fulfillment_status, :fulfilled)
      change run_oban_trigger(:send_delivered_email)
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
                     :send_delivered_email,
                     :send_order_details_email,
                     :record_link_payment,
                     :record_stripe_refund,
                     :reconcile_payment,
                     :purge_abandoned_cart
                   ])

      # The payment link page creates its PaymentIntent on a placed order.
      authorize_if action(:add_payment_intent_id)

      authorize_if action_type(:read)
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if action([
                     :mark_fulfilled,
                     :sales_summary,
                     :place_custom,
                     :edit,
                     :update_florist_note,
                     :cancel,
                     :record_in_person_payment,
                     :open_payment_link,
                     :send_order_details_email,
                     :email_receipt
                   ])

      authorize_if action_type(:read)
    end

    # Guest checkout: creating an order does not require authentication.
    policy action(:create_for_checkout) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if expr(state in ^@checkout_states)
      authorize_if expr(state == :placed and user_id == ^actor(:id))
    end

    # Placed orders are sealed for every actor; the bypasses above name the
    # few actions that may still change one.
    policy action_type(:update) do
      forbid_if expr(state == :placed)
      authorize_if expr(state in ^@checkout_states)
    end
  end

  pub_sub do
    module EdenflowersWeb.Endpoint

    publish :restart_checkout, ["order", "checkout_restarted", :id]
    publish :finalize_checkout, ["order", "placed", :id]
    publish :record_link_payment, ["order", "paid", :id]
    publish :add_promotion_with_code, ["line_item", "changed", :id]
    publish :clear_promotion, ["line_item", "changed", :id]
  end

  attributes do
    uuid_primary_key :id

    attribute :order_reference, :string

    attribute :ordered_at, :utc_datetime

    attribute :payment_status, __MODULE__.PaymentStatus, allow_nil?: false, default: :pending
    attribute :fulfillment_status, __MODULE__.FulfillmentStatus, allow_nil?: false, default: :pending
    attribute :cancelled_at, :utc_datetime

    attribute :origin, __MODULE__.Origin, allow_nil?: false, default: :online

    # Step 1 - Your Details
    attribute :customer_name, :string
    attribute :customer_email, :string
    # Only custom orders ask for it: a phone customer may have no email.
    attribute :customer_phone_number, :string

    # Step 2 - Gift Options
    attribute :gift, :boolean, allow_nil?: false, default: false
    attribute :card_message, :string

    # Step 3 - Delivery Information
    attribute :recipient_name, :string
    attribute :recipient_phone_number, :string
    attribute :delivery_address, :string
    attribute :delivery_instructions, :string
    attribute :fulfillment_date, :date
    attribute :fulfillment_fee, :decimal, constraints: [min: 0, scale: 2]
    # Set by Jennie on a custom order to charge her own fee, e.g. free delivery
    # for a regular. Nil means the fee is calculated, as at checkout.
    attribute :fulfillment_fee_override, :decimal, constraints: [min: 0, scale: 2]
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
    # The secret in a custom order's payment link URL. Nil when the customer
    # pays in person.
    attribute :payment_link_token, :string, sensitive?: true

    # Snapshotted from Promotion by ApplyPromotion. Frozen once the order
    # is placed.
    attribute :discount_rate, :decimal
    attribute :promotion_name, :string
    attribute :promotion_code, :string
    attribute :promotion_minimum_cart_total, :decimal

    attribute :locale, :string, allow_nil?: false, default: "sv-FI"

    # The SHA proves what was sent without persisting the PDF — the renderer is deterministic
    # over the placed order's snapshot columns, so a re-render should reproduce these bytes.
    attribute :receipt_emailed_at, :utc_datetime
    attribute :receipt_sha256, :string
    attribute :vat_breakdown, {:array, Edenflowers.Orders.VatRow}
    attribute :delivered_emailed_at, :utc_datetime
    # The order details a custom order's customer is sent when it is placed.
    attribute :details_emailed_at, :utc_datetime

    # Jennie's own working note. Never shown to the customer.
    attribute :florist_note, :string

    timestamps()
  end

  relationships do
    belongs_to :user, Edenflowers.Accounts.User
    belongs_to :fulfillment_option, Edenflowers.Fulfillment.FulfillmentOption
    belongs_to :promotion, Edenflowers.Pricing.Promotion
    has_many :line_items, Edenflowers.Orders.LineItem
    has_many :payments, Edenflowers.Orders.Payment
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
                not is_nil(promotion_id) and
                  (is_nil(promotion_minimum_cart_total) or items_subtotal >= promotion_minimum_cart_total)
              )

    calculate :grand_total, :decimal, expr(items_total + (fulfillment_fee || 0))
    calculate :amount_mismatch?, :boolean, expr(not is_nil(amount_paid) and amount_paid != grand_total)

    # Positive is still to collect, negative is to refund. Left by a payment of
    # the wrong amount, or by editing an order after it was paid.
    calculate :balance, :decimal, expr(grand_total - (amount_paid || 0))

    # Money still owed: placed, not paid, and not called off. A fulfilled order
    # can still be unpaid when the customer pays afterwards.
    calculate :unpaid?,
              :boolean,
              expr(state == :placed and payment_status != :paid and fulfillment_status != :cancelled)

    calculate :payment_link_open?,
              :boolean,
              expr(not is_nil(payment_link_token) and balance > 0 and fulfillment_status != :cancelled)

    calculate :vat, :decimal, Calculations.Vat

    # False until step 1 assigns the customer. An aggregate `default` doesn't
    # cover a nil `user_id`, hence the `if`.
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

    # Nil until money has moved, so a placed order with no payments reads as unpaid.
    sum :amount_paid, :payments, :amount

    # Unauthorized because the checkout actor, often a guest, can't read the
    # order's user under the User read policy.
    first :customer_newsletter_offer_hidden?, :user, :newsletter_offer_hidden? do
      authorize? false
    end
  end

  identities do
    identity :unique_order_reference, [:order_reference]
    identity :unique_payment_link_token, [:payment_link_token]
  end
end
