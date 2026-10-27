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
    :contact_phone_number,
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
    destroy :purge_abandoned_cart do
      description "Run nightly: deletes a cart that was never placed, has no lines or PaymentIntent and hasn't " <>
                    "changed for a day."

      change filter expr(
                      state != :placed and is_nil(payment_intent_id) and not exists(line_items, true) and
                        updated_at < ago(1, :day)
                    )
    end

    read :for_checkout do
      description "Reads a cart with everything the cart and checkout pages show: its lines, totals, VAT, " <>
                    "promotion and fulfillment option."

      prepare build(load: @checkout_load)
    end

    create :create_for_checkout do
      description "Opens an empty cart at contact details for a new browser session, guest or signed in. " <>
                    "Carts left empty for a day are purged nightly."
    end

    # Forward checkout transitions
    update :submit_contact_details do
      description "Checkout step 1: assigns the cart to the account for the customer's email, creating one if " <>
                    "needed, and moves to gift options. `newsletter_opt_in` also signs that account up to the " <>
                    "newsletter."

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
      description "Checkout step 2: requires a recipient for a gift, and otherwise drops the recipient, their " <>
                    "phone, the card message and card. Moves to delivery, prefilled from the signed-in customer's " <>
                    "last order."

      accept [:gift, :recipient_name, :card_message]
      validate present(:recipient_name), where: [attribute_equals(:gift, true)]
      validate Validations.CardMessageLength
      change set_attribute(:recipient_name, nil), where: attribute_equals(:gift, false)
      change set_attribute(:card_message, nil), where: attribute_equals(:gift, false)
      change set_attribute(:recipient_phone_number, nil), where: attribute_equals(:gift, false)
      change Changes.RemoveCardLineItem, where: attribute_equals(:gift, false)
      change Changes.PrefillFromLastOrder
      change transition_state(:delivery)
      require_atomic? false
    end

    update :submit_delivery do
      description "Checkout step 3: checks the date, address and phone, prices the fee server side from the " <>
                    "chosen fulfillment option, and moves to payment."

      accept [
        :fulfillment_option_id,
        :recipient_name,
        :delivery_instructions,
        :fulfillment_date,
        :delivery_address
      ]

      argument :contact_phone_number, :string do
        description "The step's one phone field. Stored as the Recipient's number on a gift delivery, otherwise " <>
                      "as the Customer's own; read it back through the contact_phone_number calculation."
      end

      change Changes.SnapshotFulfillmentMethod
      validate present(:fulfillment_date)
      validate Validations.FulfillmentDate
      validate Validations.DeliveryAddress
      validate present(:contact_phone_number)
      change {Changes.NormalizePhoneNumber, argument: :contact_phone_number}
      change Changes.SetContactPhoneNumber
      change Changes.CalculateFulfillmentCost
      change transition_state(:payment)
      require_atomic? false
    end

    # Backward "edit" transitions
    update :return_to_contact_details do
      description "Steps a cart back to contact details from any later step, keeping what was entered."
      change transition_state(:contact_details)
    end

    update :return_to_gift_options do
      description "Steps a cart back to gift options from delivery or payment, keeping what was entered."
      change transition_state(:gift_options)
    end

    update :return_to_delivery do
      description "Steps a cart back to delivery from payment, keeping what was entered."
      change transition_state(:delivery)
    end

    update :finalize_checkout do
      description "Run by the system once Stripe reports a cart's PaymentIntent paid: places it from whichever " <>
                    "checkout step it is on, records the payment, takes stock, queues the receipt, notifies the " <>
                    "shop and starts any subscription it set up. Also places a paid Occurrence."

      argument :payment_intent_id, :string, allow_nil?: false

      argument :amount_paid, :decimal,
        allow_nil?: false,
        constraints: [min: 0, scale: 2],
        description: "What Stripe charged, kept even when it differs from what is owed."

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
      description "Switches a cart's fulfillment option, clearing the old address and fee and prefilling from the " <>
                    "customer's last order."

      accept [:fulfillment_option_id]
      change Changes.SnapshotFulfillmentMethod
      change Changes.ClearDeliveryFields
      change Changes.PrefillFromLastOrder
      require_atomic? false
    end

    update :set_gift do
      description "Saves the gift toggle as the customer flips it, so the page shows the matching fields. " <>
                    "An actual flip clears the address entered so far, which was for the other person; going back " <>
                    "to For me refills the Customer's own on entering delivery. Unlike submit_gift_options, it " <>
                    "checks nothing."

      accept [:gift]
      change Changes.ClearDeliveryFields, where: [changing(:gift)]
      require_atomic? false
    end

    update :update_locale do
      description "Keeps a cart's locale in step with the language the customer is browsing in, so its emails go " <>
                    "out in it."

      accept [:locale]
      validate attribute_in(:locale, @locales)
    end

    action :prepare_checkout_payment, :map do
      description "Readies the cart's Stripe PaymentIntent and returns its client secret. Refuses incomplete " <>
                    "checkouts, unavailable dates, carts of only cards or add-ons, and stock shortages. Run as " <>
                    "the customer, or nil for a guest: the actor decides which saved cards are offered."

      argument :order_id, :uuid, allow_nil?: false
      run Actions.PrepareCheckoutPayment
    end

    update :add_promotion_with_code do
      description "Applies the promotion with this code, copying its terms onto the cart. Fails on an unknown code " <>
                    "or a cart under the promotion's minimum total."

      argument :code, :string, allow_nil?: false, constraints: [trim?: true, min_length: 1]
      change Changes.ApplyPromotion
      require_atomic? false
    end

    update :clear_promotion do
      description "Takes the promotion and the terms copied from it off the cart."
      change Changes.ClearPromotionFields
    end

    update :restart_checkout do
      description "Empties the cart and blanks every checkout field, back at contact details, on the same order so " <>
                    "the session keeps its cart. A cart with a PaymentIntent keeps who is paying, in case that " <>
                    "payment still lands."

      change Changes.ResetCheckout
      change transition_state(:contact_details)
      require_atomic? false
    end

    update :add_card do
      description "Puts a card of the given variant on the cart, replacing any card already there."
      argument :product_variant_id, :uuid, allow_nil?: false
      change Changes.SwapCardLineItem
      require_atomic? false
    end

    update :remove_card do
      description "Takes the card and its message off the cart."
      change set_attribute(:card_message, nil)
      change Changes.RemoveCardLineItem
      require_atomic? false
    end

    update :remove_line_item do
      description "Removes one line from the cart, and restarts checkout when only a card, or nothing, is left."
      argument :line_item_id, :uuid, allow_nil?: false
      change Changes.RemoveLineItem
      require_atomic? false
    end
  end
end
