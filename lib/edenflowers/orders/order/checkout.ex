defmodule Edenflowers.Orders.Order.Checkout do
  @moduledoc """
  The cart and the checkout steps an Online Order goes through until its
  payment places it.
  """

  use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshStateMachine, AshOban, AshRateLimiter]

  import Ash.Expr, only: [expr: 1]
  import Edenflowers.Actors

  alias Edenflowers.Orders.Changes.NotifyShop
  alias Edenflowers.Orders.Order.Actions
  alias Edenflowers.Orders.Order.Changes
  alias Edenflowers.Orders.Order.Validations
  alias Edenflowers.Payments.Changes, as: PaymentChanges
  alias Edenflowers.Payments.Validations, as: PaymentValidations

  @locales Edenflowers.Locales.all()
  # As long as the largest card's, and what fits on the voucher.
  @voucher_message_length 200

  # A round number on the card.
  @voucher_amounts Enum.to_list(20..200//10)

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
    :voucher_amount,
    :voucher_left_after,
    :stripe_amount,
    :card_needed?,
    :accepts_gift_voucher?,
    :available_from,
    :first_open_day,
    line_items: [:total, :product_slug, :available_from]
  ]

  @storefront_load [:total_items_in_cart, :add_ons_only?, :promotion_applied?, line_items: [:product_slug]]

  @doc "The longest message a Gift voucher can carry."
  def voucher_message_length, do: @voucher_message_length

  @doc "The amounts a Gift voucher is sold for, in whole euros."
  def voucher_amounts, do: @voucher_amounts

  oban do
    triggers do
      # Removing a cart's last line leaves it empty.
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
                  updated_at < ago(1, :day) and (is_nil(promotion_id) or updated_at < ago(30, :day))
              )
      end
    end
  end

  # Per cart. Codes are 60 random bits, so this is against hammering, not guessing.
  rate_limit do
    backend Edenflowers.RateLimiter
    action :add_gift_voucher_with_code, limit: 10, per: :timer.minutes(15), on: :before_transaction
  end

  actions do
    destroy :purge_abandoned_cart do
      description "Run nightly: deletes a cart that was never placed, has no lines or PaymentIntent and hasn't " <>
                    "changed for a day, or for 30 days if it holds a code from a link."

      change filter expr(
                      state != :placed and is_nil(payment_intent_id) and not exists(line_items, true) and
                        updated_at < ago(1, :day) and (is_nil(promotion_id) or updated_at < ago(30, :day))
                    )
    end

    read :for_checkout do
      description "Reads a cart with everything the cart and checkout pages show: its lines, totals, VAT, " <>
                    "promotion and fulfillment option."

      prepare build(load: @checkout_load)
    end

    read :for_storefront do
      description "Reads a browser's cart, if it has one yet, with just what every storefront page shows: " <>
                    "the header count and the cart drawer's lines and promotion code. Several times quicker " <>
                    "than :for_checkout, whose totals and VAT only the checkout page needs, and it runs on " <>
                    "every page view."

      argument :visitor_id, :uuid do
        allow_nil? false
        description "The visitor_id from the browser's signed session."
      end

      get? true
      filter expr(visitor_id == ^arg(:visitor_id) and state != :placed)
      prepare build(load: @storefront_load)
    end

    read :paid_with_payment_intent do
      description "The order Stripe sent a customer back for, only if this PaymentIntent paid it, or is " <>
                    "still attached to pay it. Stripe hands the id only to the browser that paid, so holding it " <>
                    "is the access, as a cart's visitor_id is: a Gift voucher sale is no browser's cart. Read " <>
                    "unauthorized, as the guest can't read Payments."

      argument :id, :uuid, allow_nil?: false
      argument :payment_intent_id, :string, allow_nil?: false
      get? true

      filter expr(
               id == ^arg(:id) and
                 (payment_intent_id == ^arg(:payment_intent_id) or
                    exists(payments, payment_intent_id == ^arg(:payment_intent_id)))
             )
    end

    create :create_for_checkout do
      description "Opens a browser's cart at contact details on its first add to cart or code link, guest or " <>
                    "signed in, or returns the cart it already has, so two tabs adding at once share one. Without " <>
                    "a visitor_id it always opens a new cart. Carts left empty for a day are purged nightly."

      argument :visitor_id, :uuid do
        description "The visitor_id from the browser's signed session."
      end

      change set_attribute(:visitor_id, arg(:visitor_id))
      upsert? true
      upsert_identity :unique_cart_per_visitor
      upsert_fields [:visitor_id]
    end

    create :start_gift_voucher_sale do
      description "Starts the Gift voucher checkout: an order holding one voucher line for the amount, from 20 " <>
                    "to 200 € in steps of 10, with who it's for, the buyer's message and the language and style of its PDF. It skips the cart's " <>
                    "steps, starting at payment, and is never a browser's cart, so a voucher can't share one " <>
                    "with flowers. Finds or creates the buyer's account by email."

      accept [
        :customer_name,
        :customer_email,
        :recipient_name,
        :card_message,
        :collect_voucher_card,
        :voucher_locale,
        :voucher_style,
        :locale
      ]

      argument :amount, :integer do
        allow_nil? false
        description "The voucher's amount in whole euros."
      end

      require_attributes [:customer_name, :customer_email, :recipient_name, :voucher_locale]
      validate attribute_in(:locale, @locales)
      validate attribute_in(:voucher_locale, @locales)
      validate Validations.VoucherStyleOffered
      validate string_length(:card_message, max: @voucher_message_length)
      validate one_of(:amount, @voucher_amounts)
      change set_new_attribute(:voucher_style, :cream)
      change set_attribute(:state, :payment)
      change set_attribute(:gift, true)
      change Changes.UpsertUserAndAssignToOrder
      change Changes.SetGiftVoucherLine
    end

    update :revise_gift_voucher_sale do
      description "Changes an unpaid Gift voucher checkout when the buyer goes back: the amount, the voucher's " <>
                    "details or the buyer's. Any PaymentIntent it has is brought up to the new amount before " <>
                    "paying. Refused once placed."

      accept [
        :customer_name,
        :customer_email,
        :recipient_name,
        :card_message,
        :collect_voucher_card,
        :voucher_locale,
        :voucher_style
      ]

      argument :amount, :integer do
        allow_nil? false
        description "The voucher's amount in whole euros."
      end

      change filter expr(state == :payment and gift_voucher_sale?)
      require_attributes [:customer_name, :customer_email, :recipient_name, :voucher_locale, :voucher_style]
      validate attribute_in(:voucher_locale, @locales)
      validate Validations.VoucherStyleOffered
      validate string_length(:card_message, max: @voucher_message_length)
      validate one_of(:amount, @voucher_amounts)
      change Changes.UpsertUserAndAssignToOrder
      change Changes.SetGiftVoucherLine
      require_atomic? false
    end

    update :release_cart do
      description "Detaches a cart from its browser when Stripe sends the customer back from paying, so their " <>
                    "next add to cart opens a new one while the webhook places this order. Only the browser " <>
                    "whose cart it is can release it, so a cross-site link can't empty someone's cart."

      argument :visitor_id, :uuid do
        allow_nil? false
        description "The visitor_id from the browser's signed session."
      end

      change filter expr(visitor_id == ^arg(:visitor_id))
      change set_attribute(:visitor_id, nil)
    end

    # Forward checkout transitions
    update :submit_contact_details do
      description "Checkout step 1: assigns the cart to the account for the customer's email, creating one if " <>
                    "needed, and moves to gift options. `newsletter_opt_in` also signs that account up to the " <>
                    "newsletter and applies their welcome code to the cart, unless it already has a code."

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
                    "phone, the card message and card. Moves to delivery, on checkout's first fulfillment option " <>
                    "unless one is chosen, prefilled from the signed-in customer's last order."

      accept [:gift, :recipient_name, :card_message]
      validate present(:recipient_name), where: [attribute_equals(:gift, true)]
      validate Validations.CardMessageLength
      change set_attribute(:recipient_name, nil), where: attribute_equals(:gift, false)
      change set_attribute(:card_message, nil), where: attribute_equals(:gift, false)
      change set_attribute(:recipient_phone_number, nil), where: attribute_equals(:gift, false)
      change Changes.RemoveCardLineItem, where: attribute_equals(:gift, false)
      change Changes.DefaultFulfillmentOption
      change Changes.SnapshotFulfillmentMethod
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
                    "shop and starts any subscription it set up. A Gift voucher sale issues its voucher, which " <>
                    "the receipt email carries. Also places a paid Occurrence."

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
      change PaymentChanges.PayFromVoucher
      change Changes.IssueGiftVouchers
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

    # finalize_checkout without Stripe; keep the two in step. A voucher always
    # leaves a subscription cart something to charge, so the card is saved and
    # there's no subscription to start here, and a voucher sale can't hold a
    # voucher, so there's none to issue. Also places an Occurrence its
    # Subscription's voucher pays in full.
    update :place_paid_by_voucher do
      description "Places a cart its Gift voucher pays for in full, as finalize_checkout does once Stripe " <>
                    "has charged a card: records the voucher payment, takes stock, queues the receipt and " <>
                    "notifies the shop. Refused, and nothing placed, unless the voucher covers the Balance. Run " <>
                    "by the system once prepare_checkout_payment has checked the cart."

      validate present(:gift_voucher_id)
      change transition_state(:placed)
      change set_attribute(:ordered_at, &DateTime.utc_now/0)
      change atomic_set(:order_reference, expr(fragment("nextval('reference_seq')::text")))
      change Changes.SnapshotVatBreakdown
      # A PaymentIntent from paying by card before the voucher went on.
      change PaymentChanges.CancelOpenPaymentIntent
      change PaymentChanges.PayFromVoucher
      change PaymentChanges.RequireSettled
      change {Changes.AdjustStock, direction: :take, report_oversell?: true}
      change Changes.ReportPromotionOverused
      change {PaymentChanges.QueueEmail, trigger: :send_receipt_email}
      change NotifyShop
      require_atomic? false
    end

    update :add_gift_voucher_with_code do
      description "Puts the Gift voucher with this code on the cart, so Stripe charges only what it doesn't " <>
                    "cover. Nothing is spent until the order is placed. Fails on an unknown, expired or used-up " <>
                    "voucher, and on a Gift voucher sale. Rate-limited: a code is money."

      argument :code, :string, allow_nil?: false, constraints: [trim?: true, min_length: 1]
      change PaymentChanges.ApplyGiftVoucher
      require_atomic? false
    end

    update :clear_gift_voucher do
      description "Takes the Gift voucher off the cart, so the card pays it all."
      change set_attribute(:gift_voucher_id, nil)
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
                    "out in it, and renames its catalogue lines in it, so its receipt names them as the " <>
                    "customer last read them."

      accept [:locale]
      require_atomic? false
      validate attribute_in(:locale, @locales)
      change Changes.RenameLinesInLocale, where: [changing(:locale)]
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

    update :add_promotion_from_link do
      description "Applies the promotion with this code from a link, even to a cart still under the promotion's " <>
                    "minimum total: the cart says so until it reaches it. Fails on an unknown or unusable code."

      argument :code, :string, allow_nil?: false, constraints: [trim?: true, min_length: 1]
      change {Changes.ApplyPromotion, check_minimum?: false}
      require_atomic? false
    end

    action :open_cart_with_code, :boolean do
      description "Puts a code from a link (`?code=` on any storefront page) on the browser's cart, opening the " <>
                    "cart if it has none yet. A code already on the cart is kept, and an unknown or used-up code " <>
                    "changes nothing, not even opening a cart. Does nothing for an admin, so Jennie scanning a card " <>
                    "to check it doesn't put it on her own cart. Returns whether the cart now carries this code."

      argument :visitor_id, :uuid do
        allow_nil? false
        description "The visitor_id from the browser's signed session."
      end

      argument :code, :string, allow_nil?: false, constraints: [trim?: true, min_length: 1]

      run fn input, context ->
        %{visitor_id: visitor_id, code: code} = input.arguments
        opts = Ash.Context.to_opts(context)

        cond do
          match?(%{admin: true}, context.actor) ->
            {:ok, false}

          match?({:error, _unusable}, Edenflowers.Pricing.get_promotion_by_code(code)) ->
            {:ok, false}

          true ->
            cart = Edenflowers.Orders.create_for_checkout!(%{visitor_id: visitor_id}, opts)

            cart =
              if is_nil(cart.promotion_id) do
                case Edenflowers.Orders.add_promotion_from_link(cart, code, opts) do
                  {:ok, cart} -> cart
                  {:error, _invalid_code} -> cart
                end
              else
                cart
              end

            {:ok, String.downcase(cart.promotion_code || "") == String.downcase(code)}
        end
      end
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
      description "Removes one line from the cart. Removing the card also clears its message. Restarts checkout when only " <>
                    "a card, or nothing, is left."

      argument :line_item_id, :uuid, allow_nil?: false
      change Changes.RemoveLineItem
      require_atomic? false
    end
  end
end
