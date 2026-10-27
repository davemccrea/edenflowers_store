defmodule Edenflowers.Orders.Order.Admin do
  @moduledoc """
  What Jennie does with orders in the admin: entering and editing Custom
  Orders, fulfilling and cancelling any order, and the lists she works from.
  """

  use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshOban]

  import Ash.Expr, only: [expr: 1]
  import Edenflowers.Actors

  alias Edenflowers.Orders.Changes.NotifyShop
  alias Edenflowers.Orders.Order.Actions
  alias Edenflowers.Orders.Order.Changes
  alias Edenflowers.Orders.Order.Validations
  alias Edenflowers.Orders.Validations.Holds
  alias Edenflowers.Payments.Changes, as: PaymentChanges

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

  @admin_show_load [
    :payment_status,
    :amount_paid,
    :amount_held,
    :refund_methods,
    :default_refund_method,
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
    :payment_reminder_sendable?,
    :receipt_available?,
    :details_emailable?,
    :fulfillment_confirmation_applicable?,
    :fulfillment_confirmation_sendable?,
    :promotion,
    :fulfillment_option,
    line_items: [:subtotal, :total]
  ]

  oban do
    triggers do
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
    end
  end

  actions do
    read :due_soon do
      description "The admin Overview's list: placed orders still to make up to 8 days ahead, overdue included, " <>
                    "by date, time and distance."

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

    # Kept apart from :due_soon so the table's loads and sorting stay out of
    # the Overview's read.
    read :admin_list do
      description "The admin orders table: every placed order, newest first, paginated, with its fulfillment " <>
                    "and payment status."

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
      description "Jennie's search of placed orders by customer, reference, phone, email, Instagram, recipient or " <>
                    "address, newest first."

      argument :term, :ci_string,
        allow_nil?: false,
        description: "Matched as part of any searched field, ignoring case."

      filter expr(state == :placed and matches?(term: ^arg(:term)))

      prepare build(sort: [ordered_at: :desc], load: [:settled?, :to_collect?, :amount_paid, :balance, :payment_status])
    end

    # What the Overview lists as still to collect or refund.
    read :unsettled do
      description "Placed orders that are not Settled, with their balance to collect or refund, for the admin Overview."
      filter expr(committed? and not settled?)
      prepare build(load: [:balance, :payment_overdue?, :customer_name, :order_reference])
    end

    read :to_fulfil do
      description "Placed orders still to make, paid or not, soonest first."
      # Unpaid custom orders still have to be made (ADR 0001).
      filter expr(state == :placed and fulfillment_status == :pending)
      prepare build(sort: [fulfillment_date: :asc, ordered_at: :asc, id: :asc], load: [:payment_status])
    end

    read :admin_show do
      description "A placed order with everything the admin order page shows, including what Jennie may still do " <>
                    "with it."

      filter expr(state == :placed)
      prepare build(load: @admin_show_load)
    end

    read :last_with_customer_phone do
      description "The customer's latest placed order that holds their own phone number, to prefill a Custom Order " <>
                    "Jennie enters for them and the phone on their next checkout."

      argument :customer_id, :uuid, allow_nil?: false
      get? true

      filter expr(state == :placed and user_id == ^arg(:customer_id) and not is_nil(customer_phone_number))

      prepare build(sort: [ordered_at: :desc], limit: 1)
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

    create :place_custom do
      description "Jennie enters a Custom Order, placed at once and possibly unpaid: opens a payment link if " <>
                    "its terms are a payment link, takes stock, and queues the Order details email unless " <>
                    "`email_customer?` is false."

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
      change {Changes.NormalizePhoneNumber, attribute: :recipient_phone_number}
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

    update :edit do
      description "Jennie changes any open order, online or custom, paid or not: stock moves with the lines, a " <>
                    "changed total leaves a Balance, and `email_customer?` queues the Order updated email."

      accept @custom_order_fields

      argument :line_items, {:array, :map}, default: []
      validate argument_does_not_equal(:line_items, []), message: "Add at least one item"
      argument :fulfillment_time, :atom, constraints: [one_of: [:any, :at, :between]]
      argument :card_variant_id, :uuid
      argument :email_customer?, :boolean, default: false
      argument :message, :string

      validate {Holds, calculation: :editable?, message: "is no longer open"}
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
      change {Changes.NormalizePhoneNumber, attribute: :recipient_phone_number}
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

    # What an order Jennie is entering or editing will cost once saved, from
    # the params :place_custom and :edit take. Saves nothing.
    action :quote_entered, :map do
      description "Prices an order Jennie is entering or editing, from the params place_custom and edit take, " <>
                    "without saving it, so she can quote a customer on the phone."

      argument :order, :struct,
        constraints: [instance_of: Edenflowers.Orders.Order],
        description: "The order being edited, or nil for a new one."

      argument :params, :map, allow_nil?: false, description: "What place_custom or edit would take."

      argument :delivery_quote, :map,
        description: "The form's lookup for a delivery address, so nothing is geocoded here."

      run Actions.QuoteEntered
    end

    update :refresh_vat_breakdown do
      description "Recomputes the stored VAT breakdown once the lines Jennie entered are saved. Run by " <>
                    "place_custom and edit."

      accept []
      change Changes.SnapshotVatBreakdown
      require_atomic? false
    end

    update :update_florist_note do
      description "Saves Jennie's private Florist Note on any order, logged only when it changed."
      accept [:florist_note]
      change set_context(%{skip_version_when_unchanged?: true})
    end

    update :mark_fulfilled do
      description "Jennie marks an open order delivered or collected. A delivery with an email queues the " <>
                    "fulfillment email, with the delivery photo when chosen, unless `email_customer?` is false."

      accept [:delivery_photo_slug, :email_delivery_photo]
      argument :email_customer?, :boolean, default: true
      argument :message, :string
      validate {Holds, calculation: :fulfillable?, message: "is no longer open"}
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

    update :remind_shop do
      description "Run by its job an hour before a placed order's time or window starts, while it is still to " <>
                    "make: notifies Jennie by email and push, once."

      accept []
      change set_attribute(:shop_reminded_at, &DateTime.utc_now/0)
      change {NotifyShop, notice: :reminder}
      require_atomic? false
    end

    # Puts the stock back. Payments.Changes.Cancel says what happens to the money.
    update :cancel do
      description "Jennie cancels a placed order, choosing what to refund and keep: card payments go back through " <>
                    "Stripe, stock returns, and the customer is emailed unless unticked. Unlike " <>
                    "cancel_by_customer, it takes any order still to make, whatever its date or payment method."

      accept [:cancellation_reason]
      argument :refund, :decimal, constraints: [scale: 2], description: "What Jennie chose to refund."

      argument :held, :decimal,
        constraints: [scale: 2],
        description: "What the order held when she opened the cancel form, so a retry never refunds twice."

      argument :email_customer?, :boolean, default: true
      # A subscription cancelled by its customer cancels its occurrences as them.
      argument :cancelled_by, :atom, default: :shop, constraints: [one_of: [:shop, :customer]]
      change set_attribute(:fulfillment_status, :cancelled)
      change PaymentChanges.Cancel
      change {Changes.AdjustStock, direction: :return}
      change load(@admin_show_load)
      require_atomic? false
    end

    update :open_payment_link do
      description "Gives an order that isn't cancelled a payment link, keeping the one it already has. For a " <>
                    "custom order paid later, or an order edited after it was paid."

      validate attribute_does_not_equal(:fulfillment_status, :cancelled), message: "is cancelled"
      change set_context(%{skip_version_when_unchanged?: true})
      change PaymentChanges.OpenPaymentLink
      change load(@admin_show_load)
      require_atomic? false
    end
  end
end
