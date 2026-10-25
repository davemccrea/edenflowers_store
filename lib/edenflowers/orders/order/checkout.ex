defmodule Edenflowers.Orders.Order.Checkout do
  @moduledoc """
  The cart and the checkout steps an Online Order goes through until its
  payment places it.
  """

  use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshStateMachine, AshOban]

  import Ash.Expr, only: [expr: 1]
  import Edenflowers.Actors

  alias Edenflowers.Orders.Changes.NotifyShop
  alias Edenflowers.Orders.Order.Actions
  alias Edenflowers.Orders.Order.Changes
  alias Edenflowers.Orders.Order.Validations
  alias Edenflowers.Payments.Changes, as: PaymentChanges
  alias Edenflowers.Payments.Validations, as: PaymentValidations

  @locales Edenflowers.Locales.all()

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

  oban do
    triggers do
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

  actions do
    destroy :purge_abandoned_cart

    read :for_checkout do
      prepare build(load: @checkout_load)
    end

    create :create_for_checkout

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
      change PaymentChanges.ReportAmountMismatch
      change Changes.ReportPromotionOverused

      change {PaymentChanges.QueueEmail, trigger: :send_receipt_email}
      change NotifyShop

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

    action :prepare_checkout_payment, :map do
      argument :order_id, :uuid, allow_nil?: false
      run Actions.PrepareCheckoutPayment
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
end
