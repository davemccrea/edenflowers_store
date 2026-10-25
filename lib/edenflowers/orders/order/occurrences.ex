defmodule Edenflowers.Orders.Order.Occurrences do
  @moduledoc """
  The orders a Subscription creates, and starting the Subscription from the
  checkout order that set it up.
  """

  use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshStateMachine, AshOban]

  import Ash.Expr, only: [expr: 1]
  import Edenflowers.Actors

  alias Edenflowers.Orders.Changes.NotifyShop
  alias Edenflowers.Orders.Order.Changes
  alias Edenflowers.Payments.Changes, as: PaymentChanges

  oban do
    triggers do
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
    end
  end

  actions do
    create :create_occurrence do
      description "Run by a Subscription's job on its Charge day: creates the Occurrence for one subscription " <>
                    "date, waiting at payment for its charge, with one line at the variant's current price and the " <>
                    "fee priced afresh."

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

    update :start_subscription do
      description "Run by its job after a paid subscription cart is placed: starts its Subscription from the " <>
                    "order's delivery details and saved card, and links the order to it as the first delivery."

      accept []
      change Changes.ActivateSubscription
      require_atomic? false
    end

    # An Occurrence whose card was refused. Jennie has committed to it, so it
    # is placed all the same (ADR 0001), and the customer is emailed a payment
    # link for it.
    update :place_unpaid_occurrence do
      description "Places an Occurrence whose card was refused, unpaid: opens a payment link, queues the payment " <>
                    "failed email and notifies the shop."

      change transition_state(:placed)
      change set_attribute(:ordered_at, &DateTime.utc_now/0)
      change atomic_set(:order_reference, expr(fragment("nextval('reference_seq')::text")))
      change Changes.SnapshotVatBreakdown
      change PaymentChanges.OpenPaymentLink
      change {PaymentChanges.QueueEmail, trigger: :send_payment_failed_email}
      # A paid Occurrence notifies the shop through :finalize_checkout.
      change NotifyShop
      require_atomic? false
    end
  end
end
