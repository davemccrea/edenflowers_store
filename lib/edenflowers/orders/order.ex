defmodule Edenflowers.Orders.Order do
  @moduledoc """
  A cart in progress or a placed order, including the details needed to fulfill
  it and the commercial snapshots needed to keep its history accurate.

  Online orders begin in checkout; Jennie enters Custom Orders in the admin;
  subscriptions create ordinary placed orders as Occurrences. Payment records
  and line items live in their own resources.

  This file holds what every order shares: its fields, lifecycle, log,
  policies and calculations. The actions live in fragments under `order/`,
  one for each side of the shop that uses them. Policies stay here, so who
  may do what reads in one place.
  """

  use Ash.Resource,
    domain: Edenflowers.Orders,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshStateMachine, AshOban, AshPaperTrail.Resource],
    fragments: [
      Edenflowers.Payments.Payable,
      Edenflowers.Orders.Order.Checkout,
      Edenflowers.Orders.Order.Occurrences,
      Edenflowers.Orders.Order.Customer,
      Edenflowers.Orders.Order.PaymentLink,
      Edenflowers.Orders.Order.Admin,
      Edenflowers.Orders.Order.Emails
    ]

  use GettextSigils, backend: EdenflowersWeb.Gettext

  import Ash.Expr, only: [expr: 1]

  alias Edenflowers.Accounts.Calculations, as: AccountCalculations
  alias Edenflowers.Fulfillment.FulfillmentOption
  alias Edenflowers.Orders.Calculations.Vat
  alias Edenflowers.Orders.Order.Calculations
  alias Edenflowers.Orders.Subscription
  alias Edenflowers.Payments.Payment

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
                     :quote_entered,
                     :update_florist_note,
                     :cancel,
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

    # Each reads the order with the access it needs itself: the cart by the
    # actor's read policy, the link by its token.
    policy action([:prepare_checkout_payment, :prepare_link_payment]) do
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

    attribute :fulfillment_status, __MODULE__.Types.FulfillmentStatus, allow_nil?: false, default: :pending
    attribute :cancelled_at, :utc_datetime
    # Why Jennie cancelled, for the customer's email and the log.
    attribute :cancellation_reason, :string
    # The customer's email can change later; the log names who was told.
    attribute :cancellation_emailed_to, :string

    attribute :origin, __MODULE__.Types.Origin, allow_nil?: false, default: :online
    # Custom orders only.
    attribute :payment_terms, __MODULE__.Types.PaymentTerms

    # Step 1 - Your Details
    attribute :customer_name, :string
    attribute :customer_email, Edenflowers.Types.Email
    # The Customer's own number, on every origin. Checkout asks for it on the
    # delivery step unless the order is a gift delivery.
    attribute :customer_phone_number, :string
    # Stored as Jennie typed it, with or without the @.
    attribute :customer_instagram, :string

    # Step 2 - Gift Options
    attribute :gift, :boolean, allow_nil?: false, default: false
    attribute :card_message, :string

    # Step 3 - Delivery Information
    attribute :recipient_name, :string
    # Only a gift's Recipient's number, never the Customer's own.
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
    belongs_to :user, Edenflowers.Accounts.User do
      description "The Customer's account: found or created from customer_email, or attached with `customer_id` " <>
                    "when Jennie places a Custom Order. Signed in or not. Nil for a cart before its first step, " <>
                    "or a Custom Order with no email and no Customer picked."
    end

    belongs_to :fulfillment_option, Edenflowers.Fulfillment.FulfillmentOption do
      description "The delivery or pickup option chosen. Its method, tax rate and name are snapshotted onto the " <>
                    "order, so read those rather than the live option for a placed order."
    end

    belongs_to :promotion, Edenflowers.Pricing.Promotion do
      description "The promotion whose code the customer entered. Its rate, name and minimum are snapshotted onto " <>
                    "the order; see promotion_applied? for whether it discounts the cart."
    end

    belongs_to :subscription, Edenflowers.Orders.Subscription do
      description "The Subscription this order started, or created it as an Occurrence. Nil for a one-off order."
    end

    has_many :line_items, Edenflowers.Orders.LineItem do
      description "What the order is for: catalogue items, Jennie's own priced items on a Custom Order, and any card."
    end

    has_many :payments, Edenflowers.Payments.Payment do
      description "Every Payment and refund on the order, by any method, oldest first. Refunds are negative."
      sort paid_at: :asc
    end
  end

  calculations do
    calculate :payment_overdue?,
              :boolean,
              expr(
                fulfillment_status == :fulfilled and balance > 0 and
                  fulfillment_date < date_add(helsinki_today(), ^(-Payment.overdue_after_days()), :day)
              ) do
      description "Handed over more than 14 days ago (Payment.overdue_after_days) and still owing a Balance. " <>
                    "Lists the order under Payment overdue on the admin Overview."
    end

    calculate :customer_first_name, :string, {AccountCalculations.FirstName, source: :customer_name} do
      description "A best guess at the first name in customer_name, for greeting the Customer in emails."
    end

    calculate :fulfillment_starts_at,
              :utc_datetime,
              expr(
                fragment(
                  "((? + ?) AT TIME ZONE ?)",
                  fulfillment_date,
                  fulfillment_time_start,
                  ^Edenflowers.ShopTime.timezone()
                )
              ) do
      description "When the order's time or window starts, read as Helsinki shop time. Nil when any time that " <>
                    "day will do. The remind_shop job uses it."
    end

    calculate :recipient_first_name, :string, {AccountCalculations.FirstName, source: :recipient_name} do
      description "A best guess at the first name in recipient_name, for checkout and emails that name the Recipient."
    end

    calculate :distance_km, :string, Calculations.DistanceKm do
      description "The snapshotted delivery distance, stored in metres, as a kilometre string rounded to a tenth " <>
                    ~s(and with no trailing zero: 12345 is "12.3", 5000 is "5". Nil for a pickup or when no ) <>
                    "distance was measured."
    end

    calculate :contact_phone_number,
              :string,
              expr(
                if gift and fulfillment_method == :delivery do
                  recipient_phone_number
                else
                  customer_phone_number
                end
              ) do
      description "The number to call or text about this order: the Recipient's for a gift delivery, otherwise " <>
                    "the Customer's own, who receives it or collects it. Checkout's phone field edits this number."
    end

    calculate :missing_delivery_phone?,
              :boolean,
              expr(fulfillment_method == :delivery and is_nil(contact_phone_number)) do
      description "A delivery with no number to call at the door. A Custom Order may be saved before Jennie has one."
    end

    calculate :promotion_applied?, :boolean, Calculations.PromotionApplied do
      description "Whether the promotion actually discounts the cart. A code stays on the order when the cart " <>
                    "drops below its minimum, but only discounts while the cart meets it."
    end

    # Derived from the cart rather than stored, so adding or removing a
    # free-delivery product changes it with nothing to reprice.
    calculate :fulfillment_fee, :decimal, expr(fee_for_cart(free_delivery?: free_delivery?)) do
      description "The delivery or pickup fee charged, in euros: the quoted fee, or 0 when a free-delivery " <>
                    "product is in the cart and the address is in the free delivery zone. Jennie's override is " <>
                    "charged as she set it. Loaded on every read."
    end

    calculate :fee_for_cart,
              :decimal,
              expr(
                if(
                  in_free_delivery_zone == true and ^arg(:free_delivery?) and is_nil(fulfillment_fee_override),
                  do: 0,
                  else: quoted_fulfillment_fee
                )
              ) do
      description "The fulfillment_fee rule with the cart's free_delivery? passed in, so a Custom Order quote " <>
                    "that isn't saved yet is charged the same way."

      argument :free_delivery?, :boolean, allow_nil?: false, allow_expr?: true
    end

    calculate :grand_total, :decimal, expr(items_total + (fulfillment_fee || 0)) do
      description "The order's total in euros, VAT included: discounted lines plus the fulfillment fee. Stays as " <>
                    "ordered after a cancellation, for the receipt."
    end

    calculate :total_due, :decimal, expr(if fulfillment_status == :cancelled, do: kept_amount, else: grand_total) do
      description "The Total due in euros, which the Balance is worked out from: the grand total, or once " <>
                    "cancelled only what Jennie kept."
    end

    calculate :committed?, :boolean, expr(state == :placed) do
      description "Placed, so money can be owed on it. A cart in checkout owes nothing."
    end

    calculate :cancelled?, :boolean, expr(fulfillment_status == :cancelled) do
      description "Cancelled by Jennie or by the Customer."
    end

    calculate :cancellable?, :boolean, expr(state == :placed and fulfillment_status == :pending) do
      description "Whether Jennie can cancel it now: placed and not yet fulfilled or cancelled."
    end

    calculate :refund_on_cancelling, :decimal, expr(if amount_held > 0, do: amount_held, else: 0) do
      description "What cancelling now would refund in euros unless Jennie keeps some: all the money still held."
    end

    calculate :editable?, :boolean, expr(state == :placed and fulfillment_status == :pending) do
      description "Whether Jennie can still edit it in the admin: placed and still to make."
    end

    calculate :fulfillable?, :boolean, expr(state == :placed and fulfillment_status == :pending) do
      description "Whether Jennie can mark it fulfilled: placed and still to make."
    end

    calculate :open?,
              :boolean,
              expr(
                fulfillment_status == :pending or
                  (fulfillment_status == :fulfilled and payment_status == :pending)
              ) do
      description "Still to make, or made but still to be paid for. The admin orders table's Open filter."
    end

    calculate :overdue?, :boolean, expr(fulfillment_status == :pending and fulfillment_date < helsinki_today()) do
      description "Still to make, though its fulfillment date has passed in Helsinki time. Flagged in the admin."
    end

    calculate :upcoming?,
              :boolean,
              expr(
                fulfillment_status == :pending and customer_status != :refunded and
                  (is_nil(fulfillment_date) or fulfillment_date >= helsinki_today())
              ) do
      description "Whether the Customer's account lists it under upcoming rather than past: still to make, " <>
                    "dated today or later in Helsinki time, or undated."
    end

    calculate :customer_status,
              __MODULE__.Types.CustomerStatus,
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
              ) do
      description "Where the order stands as its Customer reads it in their account, e.g. arriving today or " <>
                    "collected. A past date Jennie hasn't marked fulfilled stays scheduled."
    end

    calculate :matches?,
              :boolean,
              expr(
                contains(customer_name, ^arg(:term)) or contains(order_reference, ^arg(:term)) or
                  contains(customer_phone_number, ^arg(:term)) or contains(customer_email, ^arg(:term)) or
                  contains(customer_instagram, ^arg(:term)) or
                  contains(recipient_name, ^arg(:term)) or contains(delivery_address, ^arg(:term))
              ) do
      description "The admin orders search, case-insensitive: whether the term appears in the Customer's name, " <>
                    "email, phone or Instagram, the reference, the Recipient's name or the delivery address."

      argument :term, :ci_string, allow_nil?: false
    end

    calculate :payment_reminder_sendable?,
              :boolean,
              expr(
                fulfillment_status != :cancelled and (is_nil(payment_terms) or payment_terms != :invoice) and
                  not is_nil(customer_email) and to_collect?
              ) do
      description "Whether Jennie can send a Payment reminder: a Balance to collect, an email to send it to, " <>
                    "and not on invoice terms, as her invoice is its own reminder."
    end

    calculate :payment_status,
              __MODULE__.Types.PaymentStatus,
              expr(
                # A €0 order that never took money owes nothing, so it reads as paid.
                # A cancelled order that took nothing is called off, not unpaid.
                cond do
                  refunded? -> :refunded
                  fulfillment_status == :cancelled and amount_paid == 0 -> nil
                  balance <= 0 -> :paid
                  true -> :pending
                end
              ) do
      description "Paid, pending or refunded, from the Balance and Payments. Nil for a cancelled order that " <>
                    "never took any money."
    end

    calculate :paid?, :boolean, expr(committed? and payment_status == :paid and not cancelled?) do
      description "A placed, uncancelled order with nothing left to pay. The payment link page shows it as paid."
    end

    calculate :details_emailable?, :boolean, expr(committed? and not cancelled? and not is_nil(customer_email)) do
      description "Whether Jennie can email the order details: placed, not cancelled, and with an email address."
    end

    calculate :fulfillment_confirmation_applicable?,
              :boolean,
              expr(committed? and not cancelled? and fulfillment_method == :delivery) do
      description "Whether a Delivered or Left at the door email makes sense for this order at all: a placed, " <>
                    "uncancelled delivery. Pickups get none."
    end

    calculate :fulfillment_confirmation_sendable?,
              :boolean,
              expr(
                fulfillment_confirmation_applicable? and fulfillment_status == :fulfilled and not is_nil(customer_email)
              ) do
      description "Whether Jennie can send the fulfillment email again now: a delivery already marked fulfilled " <>
                    "with an email address."
    end

    calculate :receipt_available?, :boolean, expr(state == :placed and payment_status == :paid) do
      description "Placed and paid. A Custom Order is placed before it is paid, and has no receipt until it is."
    end

    calculate :unpaid?, :boolean, expr(state == :placed and payable?) do
      description "Money still owed on a placed order. A fulfilled order can still be unpaid when the customer " <>
                    "pays afterwards, and an Occurrence whose card was refused is placed unpaid."
    end

    calculate :holds_money?, :boolean, expr(amount_held > 0) do
      description "Some of the customer's money is still with the shop: paid, and not all refunded."
    end

    calculate :cancellable_by_customer?,
              :boolean,
              expr(
                state == :placed and fulfillment_status == :pending and origin == :online and
                  fulfillment_date > date_add(helsinki_today(), ^Subscription.cutoff_days(), :day) and
                  not exists(payments, method != :stripe)
              ) do
      description "Whether the Customer can cancel this Online Order from their account: still to make, on or " <>
                    "before its Change deadline, and paid only through Stripe so the refund can go back by card. " <>
                    "Jennie has bought flowers for anything closer."
    end

    # The deadline counts from the date the subscription made it for, which is
    # earlier than its fulfillment date when that day was closed.
    calculate :changes_open?,
              :boolean,
              expr(
                fulfillment_date > helsinki_today() and
                  (subscription_date || fulfillment_date) >
                    date_add(helsinki_today(), ^Subscription.cutoff_days(), :day)
              ) do
      description "An Occurrence still to come that its customer can change or call off from their account, " <>
                    "as its Change deadline hasn't passed."
    end

    calculate :cancellable_until,
              :date,
              expr(date_add(fulfillment_date, ^(-Subscription.change_deadline_days()), :day)) do
      description "The Change deadline: the last day the Customer can cancel the order themselves, 3 days before " <>
                    "its fulfillment date. Shown in the order confirmation and their account."
    end

    calculate :payment_link_open?, :boolean, expr(not is_nil(payment_link_token) and payable?) do
      description "The order has a Payment Link and something left to pay through it."
    end

    calculate :vat, :decimal, Vat do
      description "The VAT included in the grand total, in euros. A placed order reads its snapshotted " <>
                    "vat_breakdown, so later price or tax rate changes don't rewrite it."
    end

    # An aggregate `default` doesn't cover a nil `user_id`, hence the `if`.
    calculate :newsletter_offer_hidden?, :boolean, expr(if(customer_newsletter_offer_hidden?, true, false)) do
      description "Whether checkout stops offering the newsletter discount, as the Customer already subscribed " <>
                    "or used it. False until checkout's first step assigns the customer."
    end

    calculate :cart_effectively_empty?, :boolean, expr(non_card_line_item_count == 0) do
      description "The cart has nothing but a card, or nothing at all. The cart hides a lone card, so checkout " <>
                    "treats it as empty too."
    end

    calculate :add_ons_only?, :boolean, expr(non_card_line_item_count > 0 and non_add_on_line_item_count == 0) do
      description "The cart holds only Add-ons, which can't be checked out on their own. A lone card already " <>
                    "reads as an empty cart, so this is for the other add-ons."
    end
  end

  aggregates do
    sum :total_items_in_cart, :line_items, :quantity do
      description "How many items the cart holds, counting quantities, as shown beside the cart."
      default 0
    end

    sum :items_subtotal, :line_items, :subtotal do
      description "The lines' prices times quantities in euros, VAT included, before any promotion discount."
      default Decimal.new("0")
    end

    sum :items_total, :line_items, :total do
      description "The lines' totals in euros, VAT included, after any promotion discount. Excludes the " <>
                    "fulfillment fee."

      default Decimal.new("0")
    end

    sum :discount, :line_items, :discount do
      description "What the promotion takes off the lines, in euros."
      default Decimal.new("0")
    end

    count :non_card_line_item_count, :line_items do
      description "How many lines are something other than the greeting card."
      filter expr(is_card == false)
    end

    count :non_add_on_line_item_count, :line_items do
      description "How many lines are not Add-ons."
      filter expr(product.product_category.add_on == false)
    end

    exists :free_delivery?, :line_items do
      description "Whether any line's product waives the fulfillment fee inside the free delivery zone."
      filter expr(free_delivery == true)
    end

    exists :subscription?, :line_items do
      description "Whether the cart has a subscription line, so paying for it starts a Subscription."
      filter expr(not is_nil(interval_weeks))
    end

    # Unauthorized because the checkout actor, often a guest, can't read the
    # order's user under the User read policy.
    first :customer_newsletter_offer_hidden?, :user, :newsletter_offer_hidden? do
      description "The user's own newsletter_offer_hidden?. Nil without a user; read newsletter_offer_hidden? " <>
                    "instead."

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
