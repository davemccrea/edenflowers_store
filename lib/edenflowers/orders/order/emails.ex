defmodule Edenflowers.Orders.Order.Emails do
  @moduledoc """
  The emails an order sends its customer. Each is queued by the action that
  calls for it and sent once by its trigger's job (ADR 0005), except the few
  Jennie sends by hand from the order's menu.
  """

  use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshOban]

  import Edenflowers.Actors

  alias Edenflowers.Orders.Order.Changes
  alias Edenflowers.Orders.Validations.Holds
  alias Edenflowers.Payments.Changes, as: PaymentChanges

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
    end
  end

  actions do
    read :for_customer_email do
      description "Reads an order with what its Cancelled and Refund emails need: the customer's first name and " <>
                    "its Payments."

      prepare build(load: [:customer_first_name, :payments])
    end

    update :send_receipt_email do
      description "Run by its job once Stripe takes a checkout payment: emails the receipt PDF, as the order " <>
                    "confirmation or, for an Occurrence, Subscription delivery charged. Fails so the job retries."

      accept []
      transaction? false
      require_atomic? false
      change Changes.SendReceiptEmail
    end

    update :send_order_details_email do
      description "Emails a placed order's details, with its payment link when open: queued by place_custom, or " <>
                    "sent again by Jennie from the order's menu."

      accept []
      validate {Holds, calculation: :details_emailable?, message: "can't be emailed order details"}
      argument :message, :string
      transaction? false
      require_atomic? false
      change {Changes.SendOrderDetailsEmail, email: :order_details}
    end

    update :send_order_updated_email do
      description "Run by its job after Jennie edits a placed order and ticks to email the customer: the order " <>
                    "as it now stands, with its payment link when one is open, and her optional message."

      accept []
      argument :message, :string
      transaction? false
      require_atomic? false
      change {Changes.SendOrderDetailsEmail, email: :order_updated}
    end

    update :send_payment_failed_email do
      description "Run by its job when an Occurrence's card is refused: tells the customer it is placed all the " <>
                    "same and gives its payment link."

      accept []
      transaction? false
      require_atomic? false
      change {Changes.SendOrderDetailsEmail, email: :subscription_payment_failed}
    end

    update :send_payment_received_email do
      description "Run by its job: emails Payment received with the receipt PDF for amount, or else the latest " <>
                    "payment that isn't a refund, after a payment link is paid or Jennie records a payment and " <>
                    "ticks to email it. A fulfilled order settled in full gets the purchase receipt instead."

      accept []
      argument :amount, :decimal
      argument :message, :string
      transaction? false
      require_atomic? false
      change PaymentChanges.SendPaymentReceivedEmail
    end

    update :send_fulfillment_email do
      description "Run by its job: emails the customer Delivered, or Left at the door with the delivery photo when " <>
                    "Jennie chose to send it, with her optional message."

      accept []
      argument :message, :string
      transaction? false
      require_atomic? false
      change Changes.SendFulfillmentEmail
    end

    # Payment received again, from the order's menu.
    update :email_receipt do
      description "Jennie re-sends a paid order's receipt from the order's menu: Payment received, or the " <>
                    "purchase receipt once the order is fulfilled and settled."

      accept []
      argument :message, :string
      validate {Holds, calculation: :receipt_available?, message: "is not paid yet"}
      validate present(:customer_email), message: "has no email address"
      transaction? false
      require_atomic? false
      change PaymentChanges.SendPaymentReceivedEmail
    end

    # Sent by hand only. Opens a payment link if none is open.
    update :send_payment_reminder do
      description "Jennie emails a Payment reminder with the order's payment link, opening one if needed. Never " <>
                    "for a cancelled order, one on invoice terms, or one with nothing to collect."

      argument :message, :string

      validate {Holds, calculation: :payment_reminder_sendable?, message: "can't be sent a payment reminder"}

      transaction? false
      require_atomic? false
      change PaymentChanges.OpenPaymentLink
      change {Changes.SendOrderDetailsEmail, email: :payment_reminder}
    end

    # Sends with the photo choice stored by :mark_fulfilled.
    update :email_fulfillment_confirmation do
      description "Jennie queues the fulfillment email again for a fulfilled delivery, with the photo choice " <>
                    "mark_fulfilled stored."

      accept []

      validate {Holds,
                calculation: :fulfillment_confirmation_sendable?, message: "can't be emailed a fulfillment confirmation"}

      argument :message, :string
      change {PaymentChanges.QueueEmail, trigger: :send_fulfillment_email}
    end

    # AshOban passes the error to these, which the errors page already shows.
    update :record_fulfillment_email_failure do
      description "Marks that the fulfillment email ran out of attempts, for Jennie to see and send again."
      accept []
      change set_attribute(:fulfillment_email_failed_at, &DateTime.utc_now/0)
    end

    update :record_receipt_email_failure do
      description "Marks that the receipt or Payment received email ran out of attempts, for Jennie to see."
      accept []
      change set_attribute(:receipt_email_failed_at, &DateTime.utc_now/0)
    end

    update :record_order_details_email_failure do
      description "Marks that the order details, order updated or payment failed email ran out of attempts, for " <>
                    "Jennie to see."

      accept []
      change set_attribute(:order_details_email_failed_at, &DateTime.utc_now/0)
    end
  end
end
