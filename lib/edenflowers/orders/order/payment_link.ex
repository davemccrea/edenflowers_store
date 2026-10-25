defmodule Edenflowers.Orders.Order.PaymentLink do
  @moduledoc """
  A customer paying a placed order through its Payment Link, and reconciling
  any PaymentIntent, from checkout or a link, that Stripe never reported.
  """

  use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshOban]

  import Ash.Expr, only: [expr: 1]
  import Edenflowers.Actors

  alias Edenflowers.Orders.Changes
  alias Edenflowers.Payments.Changes, as: PaymentChanges

  oban do
    triggers do
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
    end
  end

  actions do
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
  end
end
