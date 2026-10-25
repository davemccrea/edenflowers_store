defmodule Edenflowers.Orders.Order.PaymentStatus do
  @moduledoc """
  The pending, paid, and refunded payment states of an order.
  """

  use Ash.Type.Enum, values: [:pending, :paid, :refunded]
end

defmodule Edenflowers.Orders.Order.FulfillmentStatus do
  @moduledoc "The pending, fulfilled, and cancelled fulfillment states of an order."

  use Ash.Type.Enum, values: [:pending, :fulfilled, :cancelled]
end

defmodule Edenflowers.Orders.Order.CustomerStatus do
  @moduledoc """
  Where an order stands, as its customer reads it beside its date. A past date
  Jennie hasn't marked fulfilled stays scheduled: it never claims a delivery
  the data doesn't support.
  """
  use Ash.Type.Enum,
    values: [
      :refunded,
      :cancelled,
      :confirmed,
      :collected,
      :delivered,
      :ready_today,
      :arriving_today,
      :for_pickup,
      :arriving,
      :pickup_scheduled,
      :delivery_scheduled
    ]
end

defmodule Edenflowers.Orders.Order.Origin do
  @moduledoc """
  An online order comes through checkout; a custom order is entered by Jennie
  in the admin; a subscription order is an Occurrence a Subscription created.
  """
  use Ash.Type.Enum, values: [:online, :custom, :subscription]
end

defmodule Edenflowers.Orders.Order.PaymentTerms do
  @moduledoc """
  How a custom order's customer will pay, as Jennie chose when placing it:
  through a payment link, by an invoice sent after fulfilment, or in person
  on delivery or pickup. The order details email tells the customer.
  """
  use Ash.Type.Enum, values: [:payment_link, :invoice, :on_fulfillment]
end

defmodule Edenflowers.Orders.Order do
  @moduledoc """
  A cart in progress or a placed order, including the details needed to fulfill
  it and the commercial snapshots needed to keep its history accurate.

  Online orders begin in checkout; Jennie enters Custom Orders in the admin;
  subscriptions create ordinary placed orders as Occurrences. Payment records
  and line items live in their own resources.
  """

  use Ash.Resource,
    domain: Edenflowers.Orders,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshStateMachine, AshOban, AshPaperTrail.Resource],
    fragments: [Edenflowers.Payments.Payable]

  use GettextSigils, backend: EdenflowersWeb.Gettext

  import Ash.Expr, only: [expr: 1]
  import Edenflowers.Actors

  alias Edenflowers.Accounts.Calculations, as: AccountCalculations
  alias Edenflowers.Fulfillment.FulfillmentOption
  alias Edenflowers.Orders.Actions
  alias Edenflowers.Orders.Calculations
  alias Edenflowers.Orders.Changes
  alias Edenflowers.Orders.Subscription
  alias Edenflowers.Orders.Validations
  alias Edenflowers.Payments.Changes, as: PaymentChanges
  alias Edenflowers.Payments.Payment
  alias Edenflowers.Payments.Validations, as: PaymentValidations

  @locales Edenflowers.Locales.all()

  @custom_order_fields [
    :locale,
    :customer_name,
    :customer_email,
    :customer_phone_number,
    :customer_instagram,
    :gift,
    :recipient_name,
    :recipient_phone_number,
    :card_message,
    :fulfillment_option_id,
    :fulfillment_date,
    :fulfillment_time_start,
    :fulfillment_time_end,
    :delivery_address,
    :delivery_instructions,
    :fulfillment_fee_override,
    :florist_note
  ]

  @checkout_load [
    :payment_status,
    :recipient_first_name,
    :total_items_in_cart,
    :discount,
    :items_subtotal,
    :items_total,
    :promotion_applied?,
    :grand_total,
    :vat,
    :cart_effectively_empty?,
    :add_ons_only?,
    :free_delivery?,
    :subscription?,
    :newsletter_offer_hidden?,
    :promotion,
    :fulfillment_option,
    line_items: [:total]
  ]

  @admin_show_load [
    :payment_status,
    :amount_paid,
    :amount_held,
    :paid_outside_stripe,
    :paid_through_stripe,
    :refundable?,
    :holds_money?,
    :balance,
    :unpaid?,
    :payment_link_open?,
    :customer_name,
    :customer_first_name,
    :grand_total,
    :settled?,
    :to_collect?,
    :to_refund?,
    :items_subtotal,
    :items_total,
    :vat,
    :discount,
    :distance_km,
    :missing_delivery_phone?,
    :cancellable?,
    :cancelled?,
    :editable?,
    :fulfillable?,
    :deletable?,
    :payment_reminder_sendable?,
    :receipt_available?,
    :details_emailable?,
    :fulfillment_confirmation_applicable?,
    :fulfillment_confirmation_sendable?,
    :promotion,
    :fulfillment_option,
    line_items: [:subtotal, :total]
  ]

  @checkout_states [:contact_details, :gift_options, :delivery, :payment]

  postgres do
    repo Edenflowers.Repo
    table "orders"
    migration_types quoted_fulfillment_fee: :decimal, fulfillment_fee_override: :decimal, kept_amount: :decimal

    check_constraints do
      check_constraint :quoted_fulfillment_fee, "orders_valid_quoted_fulfillment_fee",
        check: "quoted_fulfillment_fee >= 0 AND quoted_fulfillment_fee = round(quoted_fulfillment_fee, 2)",
        message: "must be a non-negative amount in whole cents"

      check_constraint :fulfillment_fee_override, "orders_valid_fulfillment_fee_override",
        check:
          "fulfillment_fee_override IS NULL OR (fulfillment_fee_override >= 0 AND fulfillment_fee_override = round(fulfillment_fee_override, 2))",
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

  def checkout_states, do: @checkout_states

  state_machine do
    # A custom order skips checkout: Jennie creates it already placed. An
    # Occurrence starts waiting for its charge, and checkout's own
    # finalize_checkout places it once the card is charged.
    initial_states([:contact_details, :payment, :placed])
    default_initial_state(:contact_details)

    transitions do
      transition(:submit_contact_details, from: :contact_details, to: :gift_options)
      transition(:submit_gift_options, from: :gift_options, to: :delivery)
      transition(:submit_delivery, from: :delivery, to: :payment)
      # The customer has paid, so any step they have since stepped back to still places the order.
      transition(:finalize_checkout, from: @checkout_states, to: :placed)
      transition(:place_unpaid_occurrence, from: :payment, to: :placed)

      transition(:return_to_contact_details, from: [:gift_options, :delivery, :payment], to: :contact_details)
      transition(:return_to_gift_options, from: [:delivery, :payment], to: :gift_options)
      transition(:return_to_delivery, from: :payment, to: :delivery)

      transition(:restart_checkout, from: @checkout_states, to: :contact_details)
    end
  end

  oban do
    triggers do
      # Queued by QueueEmail when Stripe takes a payment. A payment
      # Jennie records gets its receipt only when she sends one.
      trigger :send_receipt_email do
        action :send_receipt_email
        queue :default
        max_attempts 3
        lock_for_update? false
        scheduler_cron false
        worker_module_name Edenflowers.Orders.Workers.SendReceiptEmail
        scheduler_module_name Edenflowers.Orders.Schedulers.SendReceiptEmail
        default_actor system_actor()
        on_error :record_receipt_email_failure
      end

      # Queued when Jennie places a custom order and ticks "email the customer".
      trigger :send_order_details_email do
        action :send_order_details_email
        queue :default
        max_attempts 3
        lock_for_update? false
        scheduler_cron false
        worker_module_name Edenflowers.Orders.Workers.SendOrderDetailsEmail
        scheduler_module_name Edenflowers.Orders.Schedulers.SendOrderDetailsEmail
        default_actor system_actor()
        on_error :record_order_details_email_failure
      end

      # Queued when Jennie saves an edit and ticks "email the customer".
      trigger :send_order_updated_email do
        action :send_order_updated_email
        queue :default
        max_attempts 3
        lock_for_update? false
        scheduler_cron false
        worker_module_name Edenflowers.Orders.Workers.SendOrderUpdatedEmail
        scheduler_module_name Edenflowers.Orders.Schedulers.SendOrderUpdatedEmail
        default_actor system_actor()
        on_error :record_order_details_email_failure
      end

      # Queued by :place_unpaid_occurrence when an Occurrence's card is refused.
      trigger :send_payment_failed_email do
        action :send_payment_failed_email
        queue :default
        max_attempts 3
        lock_for_update? false
        scheduler_cron false
        worker_module_name Edenflowers.Orders.Workers.SendPaymentFailedEmail
        scheduler_module_name Edenflowers.Orders.Schedulers.SendPaymentFailedEmail
        default_actor system_actor()
        on_error :record_order_details_email_failure
      end

      # Queued when a payment link is paid, and by EmailReceipt when Jennie
      # records a payment and ticks it.
      trigger :send_payment_received_email do
        action :send_payment_received_email
        queue :default
        max_attempts 3
        lock_for_update? false
        scheduler_cron false
        worker_module_name Edenflowers.Orders.Workers.SendPaymentReceivedEmail
        scheduler_module_name Edenflowers.Orders.Schedulers.SendPaymentReceivedEmail
        default_actor system_actor()
        on_error :record_receipt_email_failure
      end

      # Started after the paid order is placed, never inside finalize_checkout,
      # so a Subscription that can't start never stops the order being placed
      # (ADR 0002). Placing runs this trigger straight away; the schedule only
      # retries starts that failed, so every 15 minutes is enough.
      trigger :start_subscription do
        action :start_subscription
        queue :default
        max_attempts 20
        lock_for_update? false
        scheduler_cron "*/15 * * * *"
        worker_module_name Edenflowers.Orders.Workers.StartSubscription
        scheduler_module_name Edenflowers.Orders.Schedulers.StartSubscription
        default_actor system_actor()
        where expr(state == :placed and origin == :online and subscription? and is_nil(subscription_id))
      end

      # An hour before an order's time or window starts, while it is still to
      # be made. Only within that hour, so orders long past never get one.
      trigger :remind_shop do
        action :remind_shop
        queue :default
        max_attempts 3
        lock_for_update? false
        scheduler_cron "*/5 * * * *"
        worker_module_name Edenflowers.Orders.Workers.RemindShop
        scheduler_module_name Edenflowers.Orders.Schedulers.RemindShop
        default_actor system_actor()

        where expr(
                state == :placed and fulfillment_status == :pending and is_nil(shop_reminded_at) and
                  fulfillment_starts_at > now() and fulfillment_starts_at <= datetime_add(now(), 1, :hour)
              )
      end

      # Queued only when Jennie asks for it, on :mark_fulfilled or
      # :email_fulfillment_confirmation. A job that runs out of attempts records
      # the failure for her to see and send again.
      trigger :send_fulfillment_email do
        action :send_fulfillment_email
        queue :default
        max_attempts 3
        lock_for_update? false
        scheduler_cron false
        worker_module_name Edenflowers.Orders.Workers.SendFulfillmentEmail
        scheduler_module_name Edenflowers.Orders.Schedulers.SendFulfillmentEmail
        default_actor system_actor()
        on_error :record_fulfillment_email_failure
      end

      trigger :reconcile_payment do
        action :reconcile_payment
        queue :default
        max_attempts 1
        lock_for_update? false
        scheduler_cron "*/10 * * * *"
        worker_module_name Edenflowers.Orders.Workers.ReconcilePayment
        scheduler_module_name Edenflowers.Orders.Schedulers.ReconcilePayment
        default_actor system_actor()

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
        default_actor system_actor()

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
    # Abandoned carts have no log, and a deleted Custom Order takes its log with it.
    create_version_on_destroy? false
    # An edit that changes only the lines changes nothing on the order row, but
    # still belongs in the log. RecordEnteredLineItems asks to skip an edit that
    # changed nothing at all.
    only_when_changed? false
    store_action_name? true
    ignore_attributes [:inserted_at, :updated_at]
    sensitive_attributes :redact

    # Set by RecordEnteredLineItems when the lines change: what they now are,
    # since changes_only can't see into another resource.
    metadata :items, :string
    # Jennie's message in the email an action sent, set by its Send* change.
    metadata :email_message, :string

    # on_actions only filters updates; every create is versioned unless ignored.
    ignore_actions [:create_for_checkout]

    on_actions [
      :finalize_checkout,
      :place_unpaid_occurrence,
      :place_custom,
      :edit,
      :update_florist_note,
      :cancel,
      :cancel_by_customer,
      :mark_fulfilled,
      :open_payment_link,
      :send_order_details_email,
      :send_order_updated_email,
      :send_payment_failed_email,
      :send_payment_received_email,
      :send_payment_reminder,
      :send_receipt_email,
      :send_fulfillment_email,
      :record_fulfillment_email_failure,
      :record_receipt_email_failure,
      :record_order_details_email_failure,
      :email_receipt
    ]
  end

  actions do
    defaults [:read]

    destroy :purge_abandoned_cart

    # For test orders and ones added by mistake.
    destroy :delete_custom do
      validate Validations.Deletable
      # Money may arrive while Stripe cancels the checked intent.
      change filter expr(deletable?)
      change {PaymentChanges.CancelOpenPaymentIntent, before_commit?: true}

      change {Changes.AdjustStock, direction: :return},
        where: [negate(attribute_equals(:fulfillment_status, :cancelled))]

      change Changes.DeleteOrderLog
      require_atomic? false
    end

    # What its cancelled and refunded emails need.
    read :for_customer_email do
      prepare build(load: [:customer_first_name, :payments])
    end

    read :for_checkout do
      prepare build(load: @checkout_load)
    end

    # Scoped to the actor by filter, not by policy: the admin bypass in policies grants
    # admins an unrestricted read, so an action named for the customer's own
    # order history has to narrow itself or it hands Jennie everyone's orders.
    read :mine do
      filter expr(state == :placed and user_id == ^actor(:id))

      prepare build(
                sort: [ordered_at: :desc, inserted_at: :desc],
                load: [
                  :payment_status,
                  :unpaid?,
                  :grand_total,
                  :payment_link_open?,
                  :amount_paid,
                  :cancellable_by_customer?,
                  :cancellable_until,
                  :customer_status,
                  :upcoming?,
                  :receipt_available?
                ]
              )
    end

    read :last_with_customer_phone do
      argument :customer_id, :uuid, allow_nil?: false
      get? true

      # Checkout (and its subscription occurrences) stores the buyer's phone in
      # recipient_phone_number except for gift deliveries; custom gifts keep a separate recipient.
      filter expr(
               state == :placed and user_id == ^arg(:customer_id) and
                 (not is_nil(customer_phone_number) or
                    (origin in [:online, :subscription] and
                       (gift == false or fulfillment_method == :pickup) and not is_nil(recipient_phone_number)))
             )

      prepare build(sort: [ordered_at: :desc], limit: 1)
    end

    # What the Overview lists: everything still to make up to 8 days ahead, overdue included.
    read :due_soon do
      filter expr(
               state == :placed and fulfillment_status == :pending and
                 fulfillment_date <= date_add(helsinki_today(), 8, :day)
             )

      prepare build(
                sort: [fulfillment_date: :asc, fulfillment_time_start: :asc_nils_last, distance: :asc_nils_last],
                load: [
                  :customer_name,
                  :order_reference,
                  :fulfillment_date,
                  :fulfillment_time_start,
                  :fulfillment_time_end,
                  :fulfillment_option_name,
                  :fulfillment_method,
                  :grand_total,
                  :amount_paid,
                  :balance,
                  :payment_status,
                  :non_card_line_item_count,
                  :distance_km,
                  :gift,
                  :recipient_name,
                  :card_message,
                  :missing_delivery_phone?,
                  :line_items
                ]
              )
    end

    # Table feed for /admin/orders, kept apart from :due_soon so the table's
    # loads and sorting stay out of the Overview's read.
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
                  :settled?,
                  :to_collect?,
                  :amount_paid,
                  :balance,
                  :payment_status,
                  :fulfillment_status,
                  :overdue?
                ]
              )
    end

    read :search do
      argument :term, :ci_string, allow_nil?: false

      filter expr(state == :placed and matches?(term: ^arg(:term)))

      prepare build(sort: [ordered_at: :desc], load: [:settled?, :to_collect?, :amount_paid, :balance, :payment_status])
    end

    # What the Overview lists as still to collect or refund.
    read :unsettled do
      filter expr(committed? and not settled?)
      prepare build(load: [:balance, :payment_overdue?, :customer_name, :order_reference])
    end

    read :to_fulfil do
      # Unpaid custom orders still have to be made (ADR 0001).
      filter expr(state == :placed and fulfillment_status == :pending)
      prepare build(sort: [fulfillment_date: :asc, ordered_at: :asc, id: :asc], load: [:payment_status])
    end

    read :admin_show do
      filter expr(state == :placed)
      prepare build(load: @admin_show_load)
    end

    read :by_payment_link_token do
      argument :token, :string, allow_nil?: false
      get? true
      filter expr(state == :placed and not is_nil(payment_link_token) and payment_link_token == ^arg(:token))

      prepare build(
                load: [
                  :payment_link_open?,
                  :paid?,
                  :payment_status,
                  :customer_first_name,
                  :refunded?,
                  :grand_total,
                  :amount_paid,
                  :amount_held,
                  :balance,
                  :items_total,
                  :vat,
                  line_items: [:subtotal]
                ]
              )
    end

    create :create_for_checkout

    create :place_custom do
      accept [:payment_terms | @custom_order_fields]

      argument :line_items, {:array, :map}, default: []
      validate argument_does_not_equal(:line_items, []), message: "Add at least one item"
      change set_new_attribute(:payment_terms, :payment_link)
      argument :fulfillment_time, :atom, constraints: [one_of: [:any, :at, :between]]
      argument :card_variant_id, :uuid
      argument :email_customer?, :boolean, default: true
      argument :message, :string
      argument :customer_id, :uuid

      change set_attribute(:state, :placed)
      change set_attribute(:origin, :custom)
      change set_attribute(:ordered_at, &DateTime.utc_now/0)
      change atomic_set(:order_reference, expr(fragment("nextval('reference_seq')::text")))
      change PaymentChanges.OpenPaymentLink, where: [attribute_equals(:payment_terms, :payment_link)]
      change load(:payment_status)

      # From here to PriceFulfillment, the same rules as :edit. Change both.
      validate attribute_in(:locale, @locales)
      validate present(:customer_name)

      validate present([:customer_email, :customer_phone_number, :customer_instagram], at_least: 1),
        message: "enter a phone number, an email or an Instagram handle"

      change Changes.SnapshotFulfillmentMethod
      validate present(:fulfillment_option_id)
      validate present(:fulfillment_date)
      validate Validations.FulfillmentDateNotPast
      change Changes.SetFulfillmentTime
      validate Validations.DeliveryAddress
      validate Validations.CardMessageLength
      change {Changes.NormalizePhoneNumber, attribute: :customer_phone_number}
      change Changes.NormalizePhoneNumber
      change Changes.ClearGiftFields
      change Changes.PriceFulfillment
      change manage_relationship(:customer_id, :user, type: :append)

      change Changes.UpsertUserAndAssignToOrder,
        where: [present(:customer_email), argument_equals(:customer_id, nil)]

      change Changes.EnterCardLine

      change manage_relationship(:line_items,
               type: :direct_control,
               on_match: {:update, :set_quantity},
               on_no_match: {:create, :enter},
               on_missing: {:destroy, :remove_item},
               authorize?: false
             )

      change Changes.RecordEnteredLineItems
      change {Changes.AdjustStock, direction: :take}

      change {PaymentChanges.QueueEmail, trigger: :send_order_details_email},
        where: [argument_equals(:email_customer?, true)]
    end

    # An Occurrence, made by Subscription's :create_occurrence. Delivery is
    # priced afresh, and the line item comes from the variant at its current
    # price, as when it is added to a cart.
    create :create_occurrence do
      accept [
        :subscription_id,
        :subscription_date,
        :user_id,
        :customer_name,
        :customer_email,
        :locale,
        :recipient_name,
        :recipient_phone_number,
        :delivery_address,
        :delivery_instructions,
        :fulfillment_option_id,
        :fulfillment_date
      ]

      argument :product_variant_id, :uuid, allow_nil?: false

      change set_attribute(:state, :payment)
      change set_attribute(:origin, :subscription)
      change Changes.SnapshotFulfillmentMethod
      change Changes.SetGiftFromRecipient
      change Changes.PriceFulfillment

      change after_action(fn changeset, order, context ->
               variant_id = Ash.Changeset.get_argument(changeset, :product_variant_id)

               with {:ok, _line_item} <-
                      Edenflowers.Orders.add_line_item(order.id, variant_id, 1, Ash.Context.to_opts(context)) do
                 {:ok, order}
               end
             end)
    end

    # Forward checkout transitions
    update :submit_contact_details do
      accept [:customer_name, :customer_email]
      require_attributes [:customer_name, :customer_email]

      argument :newsletter_opt_in, :boolean, default: false

      # On an update require_attributes only refuses an explicit nil, so an
      # email never given would reach the upsert and fail there instead.
      validate present(:customer_email)
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
      change Changes.PrefillFromLastOrder
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
      argument :paid_with, :map, default: %{}
      accept [:stripe_customer_id, :stripe_payment_method_id]
      validate PaymentValidations.MatchesPaymentIntent

      change transition_state(:placed), always_atomic?: true
      # The PaymentIntent is spent; a later payment link must open a fresh one.
      change set_attribute(:payment_intent_id, nil)
      change set_attribute(:ordered_at, &DateTime.utc_now/0)
      change atomic_set(:order_reference, expr(fragment("nextval('reference_seq')::text")))
      change Changes.SnapshotVatBreakdown
      change {PaymentChanges.RecordPayment, method: :stripe, amount: :amount_paid}
      change {Changes.AdjustStock, direction: :take, report_oversell?: true}
      change Changes.ReportAmountMismatch
      change Changes.ReportPromotionOverused

      change {PaymentChanges.QueueEmail, trigger: :send_receipt_email}
      change Changes.NotifyShop

      # Starts the Subscription straight away, so the confirmation page's link
      # to it has something to show. Outside the transaction, so a failed
      # enqueue never stops the order being placed; the trigger's scheduler
      # picks it up instead.
      change after_transaction(fn
               _changeset, {:ok, order} = result, _context ->
                 with {:ok, %{subscription?: true}} <- Ash.load(order, :subscription?, authorize?: false) do
                   AshOban.run_trigger(order, :start_subscription)
                 end

                 result

               _changeset, result, _context ->
                 result
             end)

      require_atomic? false
    end

    update :remind_shop do
      accept []
      change set_attribute(:shop_reminded_at, &DateTime.utc_now/0)
      change {Changes.NotifyShop, notice: :reminder}
      require_atomic? false
    end

    update :start_subscription do
      accept []
      change Changes.ActivateSubscription
      require_atomic? false
    end

    # An Occurrence whose card was refused. Jennie has committed to it, so it
    # is placed all the same (ADR 0001), and the customer is emailed a payment
    # link for it.
    update :place_unpaid_occurrence do
      change transition_state(:placed)
      change set_attribute(:ordered_at, &DateTime.utc_now/0)
      change atomic_set(:order_reference, expr(fragment("nextval('reference_seq')::text")))
      change Changes.SnapshotVatBreakdown
      change PaymentChanges.OpenPaymentLink
      change {PaymentChanges.QueueEmail, trigger: :send_payment_failed_email}
      # A paid Occurrence notifies the shop through :finalize_checkout.
      change Changes.NotifyShop
      require_atomic? false
    end

    # Jennie can change anything on an open order, online or custom, paid or
    # not. A paid order whose total changes is left with a balance to collect
    # or refund; an unpaid one's payment link charges the new total.
    update :edit do
      accept @custom_order_fields

      argument :line_items, {:array, :map}, default: []
      validate argument_does_not_equal(:line_items, []), message: "Add at least one item"
      argument :fulfillment_time, :atom, constraints: [one_of: [:any, :at, :between]]
      argument :card_variant_id, :uuid
      argument :email_customer?, :boolean, default: false
      argument :message, :string

      validate {Validations.Holds, calculation: :editable?, message: "is no longer open"}
      # On the UPDATE too, so an order cancelled or fulfilled since the check
      # matches no row and stock moves only once.
      change filter expr(editable?)

      # From here to PriceFulfillment, the same rules as :place_custom. Change both.
      validate attribute_in(:locale, @locales)
      validate present(:customer_name)

      validate present([:customer_email, :customer_phone_number, :customer_instagram], at_least: 1),
        message: "enter a phone number, an email or an Instagram handle"

      change Changes.SnapshotFulfillmentMethod
      validate present(:fulfillment_option_id)
      validate present(:fulfillment_date)
      validate Validations.FulfillmentDateNotPast
      change Changes.SetFulfillmentTime
      validate Validations.DeliveryAddress
      validate Validations.CardMessageLength
      change {Changes.NormalizePhoneNumber, attribute: :customer_phone_number}
      change Changes.NormalizePhoneNumber
      change Changes.ClearGiftFields
      change Changes.PriceFulfillment
      change set_attribute(:user_id, nil), where: [changing(:customer_email)]
      change Changes.UpsertUserAndAssignToOrder, where: [present(:customer_email)]
      # The old lines go back on the shelf before the new ones are taken.
      change {Changes.AdjustStock, direction: :return}

      change Changes.EnterCardLine

      change manage_relationship(:line_items,
               type: :direct_control,
               on_match: {:update, :set_quantity},
               on_no_match: {:create, :enter},
               on_missing: {:destroy, :remove_item},
               authorize?: false
             )

      change Changes.RecordEnteredLineItems
      change {Changes.AdjustStock, direction: :take}

      change {PaymentChanges.QueueEmail, trigger: :send_order_updated_email},
        where: [argument_equals(:email_customer?, true), present(:customer_email)]

      require_atomic? false
    end

    update :update_florist_note do
      accept [:florist_note]
      change set_context(%{skip_version_when_unchanged?: true})
    end

    # Puts the stock back. Payments.Changes.Cancel says what happens to the money.
    update :cancel do
      accept [:cancellation_reason]
      argument :refund, :decimal, constraints: [scale: 2]
      argument :held, :decimal, constraints: [scale: 2]
      argument :email_customer?, :boolean, default: true
      # A subscription cancelled by its customer cancels its occurrences as them.
      argument :cancelled_by, :atom, default: :shop, constraints: [one_of: [:shop, :customer]]
      change set_attribute(:fulfillment_status, :cancelled)
      change PaymentChanges.Cancel
      change {Changes.AdjustStock, direction: :return}
      change load(@admin_show_load)
      require_atomic? false
    end

    update :cancel_by_customer do
      validate Validations.CancellableByCustomer
      change set_attribute(:fulfillment_status, :cancelled)
      change {PaymentChanges.Cancel, cancelled_by: :customer}
      change {Changes.AdjustStock, direction: :return}
      change {Changes.NotifyShop, notice: :cancelled}
      require_atomic? false
    end

    # A payment through the payment link: a custom order's first payment, or
    # a balance left by editing any order. The order is already placed, so
    # unlike finalize_checkout this only records the payment.
    update :record_link_payment do
      argument :payment_intent_id, :string, allow_nil?: false
      argument :amount_paid, :decimal, allow_nil?: false, constraints: [min: 0, scale: 2]
      argument :paid_with, :map, default: %{}
      # No check that this is the order's current PaymentIntent: see ClearPaidPaymentIntent.
      change PaymentChanges.ClearPaidPaymentIntent

      change {PaymentChanges.RecordPayment, method: :stripe, amount: :amount_paid}
      change Changes.ReportUnexpectedPayment
      change Changes.ReactivateSubscription, where: [attribute_equals(:origin, :subscription)]
      # A phone customer pays a texted link and has no address to send a receipt to.
      change {PaymentChanges.QueueEmail, trigger: :send_payment_received_email, arguments: [amount: :amount_paid]},
        where: [present(:customer_email)]

      require_atomic? false
    end

    # Any order owing money can have a link: a custom order paid later, or an
    # order edited after it was paid.
    update :open_payment_link do
      validate attribute_does_not_equal(:fulfillment_status, :cancelled), message: "is cancelled"
      change set_context(%{skip_version_when_unchanged?: true})
      change PaymentChanges.OpenPaymentLink
      change load(@admin_show_load)
      require_atomic? false
    end

    # The payment link page asks for an email when Jennie took the order
    # without one, so the customer gets a receipt. An email already on the
    # order is never replaced from the link.
    update :add_customer_email do
      accept [:customer_email]
      validate present(:customer_email)
      change filter expr(is_nil(customer_email))
      change Changes.UpsertUserAndAssignToOrder
      require_atomic? false
    end

    update :send_order_details_email do
      accept []
      validate {Validations.Holds, calculation: :details_emailable?, message: "can't be emailed order details"}
      argument :message, :string
      transaction? false
      require_atomic? false
      change {Changes.SendOrderDetailsEmail, email: :order_details}
    end

    update :send_order_updated_email do
      accept []
      argument :message, :string
      transaction? false
      require_atomic? false
      change {Changes.SendOrderDetailsEmail, email: :order_updated}
    end

    update :send_payment_failed_email do
      accept []
      transaction? false
      require_atomic? false
      change {Changes.SendOrderDetailsEmail, email: :subscription_payment_failed}
    end

    # Payment received again, from the order's menu.
    update :email_receipt do
      accept []
      argument :message, :string
      validate {Validations.Holds, calculation: :receipt_available?, message: "is not paid yet"}
      validate present(:customer_email), message: "has no email address"
      transaction? false
      require_atomic? false
      change PaymentChanges.SendPaymentReceivedEmail
    end

    # Sent by hand only. Opens a payment link if none is open.
    update :send_payment_reminder do
      argument :message, :string

      validate {Validations.Holds,
                calculation: :payment_reminder_sendable?, message: "can't be sent a payment reminder"}

      transaction? false
      require_atomic? false
      change PaymentChanges.OpenPaymentLink
      change {Changes.SendOrderDetailsEmail, email: :payment_reminder}
    end

    update :send_payment_received_email do
      accept []
      argument :amount, :decimal
      argument :message, :string
      transaction? false
      require_atomic? false
      change PaymentChanges.SendPaymentReceivedEmail
    end

    update :refresh_vat_breakdown do
      accept []
      change Changes.SnapshotVatBreakdown
      require_atomic? false
    end

    update :update_fulfillment_option do
      accept [:fulfillment_option_id]
      change Changes.SnapshotFulfillmentMethod
      change Changes.ClearDeliveryFields
      change Changes.PrefillFromLastOrder
      require_atomic? false
    end

    update :set_gift do
      accept [:gift]
    end

    update :update_locale do
      accept [:locale]
      validate attribute_in(:locale, @locales)
    end

    update :send_receipt_email do
      accept []
      transaction? false
      require_atomic? false
      change Changes.SendReceiptEmail
    end

    update :send_fulfillment_email do
      accept []
      argument :message, :string
      transaction? false
      require_atomic? false
      change Changes.SendFulfillmentEmail
    end

    # AshOban passes the error to these, which the errors page already shows.
    update :record_fulfillment_email_failure do
      accept []
      change set_attribute(:fulfillment_email_failed_at, &DateTime.utc_now/0)
    end

    update :record_receipt_email_failure do
      accept []
      change set_attribute(:receipt_email_failed_at, &DateTime.utc_now/0)
    end

    update :record_order_details_email_failure do
      accept []
      change set_attribute(:order_details_email_failed_at, &DateTime.utc_now/0)
    end

    action :sales_summary, :map do
      description "Counts paid orders placed between two dates, inclusive, in Helsinki time, and sums the money " <>
                    "received in that range, refunds taken off, in total and for each day."

      constraints fields: [
                    order_count: [type: :integer, allow_nil?: false],
                    revenue: [type: :decimal, allow_nil?: false, constraints: [scale: 2]],
                    revenue_by_day: [type: {:array, :map}, allow_nil?: false]
                  ]

      argument :from, :date, allow_nil?: false
      argument :to, :date, allow_nil?: false

      run Actions.SalesSummary
    end

    # Sends with the photo choice stored by :mark_fulfilled.
    update :email_fulfillment_confirmation do
      accept []

      validate {Validations.Holds,
                calculation: :fulfillment_confirmation_sendable?, message: "can't be emailed a fulfillment confirmation"}

      argument :message, :string
      change {PaymentChanges.QueueEmail, trigger: :send_fulfillment_email}
    end

    update :mark_fulfilled do
      accept [:delivery_photo_slug, :email_delivery_photo]
      argument :email_customer?, :boolean, default: true
      argument :message, :string
      validate {Validations.Holds, calculation: :fulfillable?, message: "is no longer open"}
      change set_attribute(:fulfillment_status, :fulfilled)
      change set_attribute(:email_delivery_photo, false), where: [argument_equals(:email_customer?, false)]

      validate present(:delivery_photo_slug),
        where: [
          argument_equals(:email_customer?, true),
          attribute_equals(:fulfillment_method, :delivery),
          attribute_equals(:email_delivery_photo, true)
        ]

      # A collected order isn't emailed: the customer was there.
      change {PaymentChanges.QueueEmail, trigger: :send_fulfillment_email},
        where: [
          argument_equals(:email_customer?, true),
          attribute_equals(:fulfillment_method, :delivery),
          present(:customer_email)
        ]

      change load(@admin_show_load)
      require_atomic? false
    end

    update :add_promotion_with_code do
      argument :code, :string, allow_nil?: false, constraints: [trim?: true, min_length: 1]
      change Changes.ApplyPromotion
      require_atomic? false
    end

    update :clear_promotion do
      change Changes.ClearPromotionFields
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
                     :create_occurrence,
                     :place_unpaid_occurrence,
                     :start_subscription,
                     :mark_payment_cancelled,
                     :send_receipt_email,
                     :send_fulfillment_email,
                     :remind_shop,
                     :record_fulfillment_email_failure,
                     :record_receipt_email_failure,
                     :record_order_details_email_failure,
                     :send_order_details_email,
                     :send_order_updated_email,
                     :send_payment_failed_email,
                     :send_payment_received_email,
                     :record_link_payment,
                     :record_stripe_refund,
                     :reconcile_payment,
                     :purge_abandoned_cart
                   ])

      # The payment link page creates its PaymentIntent on a placed order.
      authorize_if action(:add_payment_intent_id)
      authorize_if action(:add_customer_email)

      authorize_if action_type(:read)
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if action([
                     :mark_fulfilled,
                     :email_fulfillment_confirmation,
                     :sales_summary,
                     :place_custom,
                     :edit,
                     :update_florist_note,
                     :cancel,
                     :delete_custom,
                     :record_payment,
                     :undo_payment,
                     :refund,
                     :open_payment_link,
                     :send_order_details_email,
                     :send_payment_reminder,
                     :email_receipt
                   ])

      authorize_if action_type(:read)
    end

    # Guest checkout: creating an order does not require authentication.
    policy action(:create_for_checkout) do
      authorize_if always()
    end

    bypass action(:cancel_by_customer) do
      authorize_if expr(user_id == ^actor(:id))
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
    # The admin is an installed app without pull to refresh, so every change
    # to a placed order, by anyone, refreshes the admin pages showing it.
    # Carts are left out: they change with every checkout step.
    publish :place_custom, ["admin", "orders"]
    publish_all :update, ["admin", "orders"], filter: fn %{data: order} -> order.state == :placed end
    publish :delete_custom, ["admin", "orders"]
    publish_all :update, ["order", "changed", :id], filter: fn %{data: order} -> order.state == :placed end
    publish :add_promotion_with_code, ["line_item", "changed", :id]
    publish :clear_promotion, ["line_item", "changed", :id]
  end

  # Every read and write returns the charged fee, so code that shows or totals
  # an order reads `fulfillment_fee` as it did when the fee was stored.
  preparations do
    prepare build(load: [:fulfillment_fee])
  end

  changes do
    change load(:fulfillment_fee), on: [:create, :update]
  end

  attributes do
    uuid_primary_key :id

    attribute :order_reference, :string

    attribute :ordered_at, :utc_datetime

    attribute :fulfillment_status, __MODULE__.FulfillmentStatus, allow_nil?: false, default: :pending
    attribute :cancelled_at, :utc_datetime
    # Why Jennie cancelled, for the customer's email and the log.
    attribute :cancellation_reason, :string
    # The customer's email can change later; the log names who was told.
    attribute :cancellation_emailed_to, :string

    attribute :origin, __MODULE__.Origin, allow_nil?: false, default: :online
    # Custom orders only.
    attribute :payment_terms, __MODULE__.PaymentTerms

    # Step 1 - Your Details
    attribute :customer_name, :string
    attribute :customer_email, Edenflowers.Types.Email
    # Only custom orders ask for it: a phone customer may have no email.
    attribute :customer_phone_number, :string
    # Stored as Jennie typed it, with or without the @.
    attribute :customer_instagram, :string

    # Step 2 - Gift Options
    attribute :gift, :boolean, allow_nil?: false, default: false
    attribute :card_message, :string

    # Step 3 - Delivery Information
    attribute :recipient_name, :string
    attribute :recipient_phone_number, :string
    attribute :delivery_address, :string
    attribute :delivery_instructions, :string
    attribute :fulfillment_date, :date
    # Only Custom Orders have these for now; checkout doesn't ask for a time.
    attribute :fulfillment_time_start, :time
    attribute :fulfillment_time_end, :time
    # The Subscription's date an Occurrence was made for. Its fulfillment_date
    # is later when that day was closed.
    attribute :subscription_date, :date
    # The fee for the address and option, before a free-delivery cart waives it;
    # see the `fulfillment_fee` calculation for what is charged.
    attribute :quoted_fulfillment_fee, :decimal, constraints: [min: 0, scale: 2]
    attribute :in_free_delivery_zone, :boolean
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
    # The card a subscription cart saved, which its Subscription is started with.
    attribute :stripe_customer_id, :string
    attribute :stripe_payment_method_id, :string
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

    attribute :receipt_emailed_at, :utc_datetime
    attribute :shop_reminded_at, :utc_datetime
    # The last queued receipt ran out of attempts. Cleared by a successful send.
    attribute :receipt_email_failed_at, :utc_datetime
    attribute :vat_breakdown, {:array, Edenflowers.Orders.VatRow}
    attribute :fulfillment_emailed_at, :utc_datetime
    # The customer's email can change later; the log names who was sent it.
    attribute :fulfillment_emailed_to, :string
    # Where Jennie left a delivery nobody answered the door for.
    attribute :delivery_photo_slug, :string
    # Sends the photo in place of the fulfillment email.
    attribute :email_delivery_photo, :boolean, allow_nil?: false, default: false
    # The last queued send ran out of attempts. Cleared by a successful send.
    attribute :fulfillment_email_failed_at, :utc_datetime
    # The order details a custom order's customer is sent when it is placed.
    attribute :order_details_emailed_at, :utc_datetime
    attribute :order_details_email_failed_at, :utc_datetime

    # Jennie's own working note. Never shown to the customer.
    attribute :florist_note, :string

    timestamps()
  end

  relationships do
    belongs_to :user, Edenflowers.Accounts.User
    belongs_to :fulfillment_option, Edenflowers.Fulfillment.FulfillmentOption
    belongs_to :promotion, Edenflowers.Pricing.Promotion
    # The Subscription this order started or was created by.
    belongs_to :subscription, Edenflowers.Orders.Subscription
    has_many :line_items, Edenflowers.Orders.LineItem

    has_many :payments, Edenflowers.Payments.Payment do
      sort paid_at: :asc
    end
  end

  calculations do
    calculate :payment_overdue?,
              :boolean,
              expr(
                fulfillment_status == :fulfilled and balance > 0 and
                  fulfillment_date < date_add(helsinki_today(), ^(-Payment.overdue_after_days()), :day)
              )

    calculate :customer_first_name, :string, {AccountCalculations.FirstName, source: :customer_name}

    # When the order's time or window starts, in shop time. Nil when any time that day will do.
    calculate :fulfillment_starts_at,
              :utc_datetime,
              expr(
                fragment(
                  "((? + ?) AT TIME ZONE ?)",
                  fulfillment_date,
                  fulfillment_time_start,
                  ^Edenflowers.ShopTime.timezone()
                )
              )

    calculate :recipient_first_name, :string, {AccountCalculations.FirstName, source: :recipient_name}

    # `distance` is snapshotted in metres; expose it as a kilometre string for
    # display, and only for deliveries.
    calculate :distance_km, :string, Calculations.DistanceKm

    # A Custom Order may be saved before Jennie has a number to call at the
    # door: the recipient's for a gift, otherwise the customer's own.
    calculate :missing_delivery_phone?,
              :boolean,
              expr(
                fulfillment_method == :delivery and is_nil(recipient_phone_number) and
                  (gift or is_nil(customer_phone_number))
              )

    # A code stays on the order when the cart drops below its minimum, but
    # only discounts while the cart meets it.
    calculate :promotion_applied?,
              :boolean,
              expr(
                not is_nil(promotion_id) and
                  (is_nil(promotion_minimum_cart_total) or items_subtotal >= promotion_minimum_cart_total)
              )

    # Derived from the cart rather than stored, so adding or removing a
    # free-delivery product changes it with nothing to reprice. Jennie's own
    # fee is charged as she set it.
    calculate :fulfillment_fee, :decimal, expr(fee_for_cart(free_delivery?: free_delivery?))

    # The rule itself, with the cart passed in, so a quote that isn't on an
    # order yet can be charged the same way.
    calculate :fee_for_cart,
              :decimal,
              expr(
                if(
                  in_free_delivery_zone == true and ^arg(:free_delivery?) and is_nil(fulfillment_fee_override),
                  do: 0,
                  else: quoted_fulfillment_fee
                )
              ) do
      argument :free_delivery?, :boolean, allow_nil?: false, allow_expr?: true
    end

    calculate :grand_total, :decimal, expr(items_total + (fulfillment_fee || 0))
    calculate :total_due, :decimal, expr(if fulfillment_status == :cancelled, do: kept_amount, else: grand_total)
    calculate :committed?, :boolean, expr(state == :placed)
    calculate :cancelled?, :boolean, expr(fulfillment_status == :cancelled)
    calculate :cancellable?, :boolean, expr(state == :placed and fulfillment_status == :pending)
    calculate :refund_on_cancelling, :decimal, expr(if amount_held > 0, do: amount_held, else: 0)
    calculate :editable?, :boolean, expr(state == :placed and fulfillment_status == :pending)
    calculate :fulfillable?, :boolean, expr(state == :placed and fulfillment_status == :pending)

    # Only a Custom Order no money has moved for. Any other is cancelled
    # instead, so the accounts stay whole.
    calculate :deletable?, :boolean, expr(origin == :custom and not exists(payments, true))

    # Still to make, or made but still to be paid for.
    calculate :open?,
              :boolean,
              expr(fulfillment_status == :pending or (fulfillment_status == :fulfilled and payment_status == :pending))

    calculate :overdue?, :boolean, expr(fulfillment_status == :pending and fulfillment_date < helsinki_today())

    calculate :upcoming?,
              :boolean,
              expr(
                fulfillment_status == :pending and customer_status != :refunded and
                  (is_nil(fulfillment_date) or fulfillment_date >= helsinki_today())
              )

    calculate :customer_status,
              __MODULE__.CustomerStatus,
              expr(
                cond do
                  payment_status == :refunded -> :refunded
                  fulfillment_status == :cancelled -> :cancelled
                  is_nil(fulfillment_date) -> :confirmed
                  fulfillment_status == :fulfilled and fulfillment_method == :pickup -> :collected
                  fulfillment_status == :fulfilled -> :delivered
                  fulfillment_date == helsinki_today() and fulfillment_method == :pickup -> :ready_today
                  fulfillment_date == helsinki_today() -> :arriving_today
                  fulfillment_date > helsinki_today() and fulfillment_method == :pickup -> :for_pickup
                  fulfillment_date > helsinki_today() -> :arriving
                  fulfillment_method == :pickup -> :pickup_scheduled
                  true -> :delivery_scheduled
                end
              )

    # What Jennie may search an order by: who it's for, its reference, or where it goes.
    calculate :matches?,
              :boolean,
              expr(
                contains(customer_name, ^arg(:term)) or contains(order_reference, ^arg(:term)) or
                  contains(customer_phone_number, ^arg(:term)) or contains(customer_email, ^arg(:term)) or
                  contains(customer_instagram, ^arg(:term)) or
                  contains(recipient_name, ^arg(:term)) or contains(delivery_address, ^arg(:term))
              ) do
      argument :term, :ci_string, allow_nil?: false
    end

    # Not for an order paid by invoice: Jennie's invoice is its reminder.
    calculate :payment_reminder_sendable?,
              :boolean,
              expr(
                fulfillment_status != :cancelled and (is_nil(payment_terms) or payment_terms != :invoice) and
                  not is_nil(customer_email) and to_collect?
              )

    calculate :payment_status,
              __MODULE__.PaymentStatus,
              expr(
                # A €0 order that never took money owes nothing, so it reads as paid.
                # A cancelled order that took nothing is called off, not unpaid.
                cond do
                  refunded? -> :refunded
                  fulfillment_status == :cancelled and amount_paid == 0 -> nil
                  balance <= 0 -> :paid
                  true -> :pending
                end
              )

    calculate :paid?, :boolean, expr(committed? and payment_status == :paid and not cancelled?)

    calculate :details_emailable?, :boolean, expr(committed? and not cancelled? and not is_nil(customer_email))

    calculate :fulfillment_confirmation_applicable?,
              :boolean,
              expr(committed? and not cancelled? and fulfillment_method == :delivery)

    calculate :fulfillment_confirmation_sendable?,
              :boolean,
              expr(
                fulfillment_confirmation_applicable? and fulfillment_status == :fulfilled and not is_nil(customer_email)
              )

    # A custom order is placed before it is paid, and has no receipt until it is.
    calculate :receipt_available?, :boolean, expr(state == :placed and payment_status == :paid)

    # Money still owed on a placed order. A fulfilled order can still be unpaid
    # when the customer pays afterwards.
    calculate :unpaid?, :boolean, expr(state == :placed and payable?)

    # Some of the customer's money is still with us: paid, and not all refunded.
    calculate :holds_money?, :boolean, expr(amount_held > 0)

    # Jennie has had time to buy flowers for anything closer, so the customer
    # gets the same notice as for a subscription change. Money paid outside
    # Stripe can't be refunded through Stripe, so those orders go through her.
    calculate :cancellable_by_customer?,
              :boolean,
              expr(
                state == :placed and fulfillment_status == :pending and origin == :online and
                  fulfillment_date > date_add(helsinki_today(), ^Subscription.cutoff_days(), :day) and
                  not exists(payments, method != :stripe)
              )

    # An Occurrence still to come that its customer can change or call off.
    # The deadline counts from the date the subscription made it for, which is
    # earlier than its fulfillment date when that day was closed.
    calculate :changes_open?,
              :boolean,
              expr(
                fulfillment_date > helsinki_today() and
                  (subscription_date || fulfillment_date) >
                    date_add(helsinki_today(), ^Subscription.cutoff_days(), :day)
              )

    calculate :cancellable_until,
              :date,
              expr(date_add(fulfillment_date, ^(-Subscription.change_deadline_days()), :day))

    calculate :payment_link_open?, :boolean, expr(not is_nil(payment_link_token) and payable?)

    calculate :vat, :decimal, Calculations.Vat

    # False until step 1 assigns the customer. An aggregate `default` doesn't
    # cover a nil `user_id`, hence the `if`.
    calculate :newsletter_offer_hidden?, :boolean, expr(if(customer_newsletter_offer_hidden?, true, false))

    # The cart hides a lone card, so checkout treats it as empty too.
    calculate :cart_effectively_empty?, :boolean, expr(non_card_line_item_count == 0)

    # A lone card already reads as an empty cart, so this is for the other add-ons.
    calculate :add_ons_only?, :boolean, expr(non_card_line_item_count > 0 and non_add_on_line_item_count == 0)
  end

  aggregates do
    sum :total_items_in_cart, :line_items, :quantity, default: 0
    sum :items_subtotal, :line_items, :subtotal, default: Decimal.new("0")
    sum :items_total, :line_items, :total, default: Decimal.new("0")
    sum :discount, :line_items, :discount, default: Decimal.new("0")
    count :non_card_line_item_count, :line_items, filter: expr(is_card == false)
    count :non_add_on_line_item_count, :line_items, filter: expr(product.product_category.add_on == false)
    exists :free_delivery?, :line_items, filter: expr(free_delivery == true)
    exists :subscription?, :line_items, filter: expr(not is_nil(interval_weeks))

    # Unauthorized because the checkout actor, often a guest, can't read the
    # order's user under the User read policy.
    first :customer_newsletter_offer_hidden?, :user, :newsletter_offer_hidden? do
      authorize? false
    end
  end

  identities do
    identity :unique_order_reference, [:order_reference]
    identity :unique_payment_link_token, [:payment_link_token]
    # One Occurrence per subscription date, however often its job runs.
    identity :unique_occurrence, [:subscription_id, :subscription_date]
  end
end
