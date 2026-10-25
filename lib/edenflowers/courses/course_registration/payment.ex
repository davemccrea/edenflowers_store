defmodule Edenflowers.Courses.CourseRegistration.Payment do
  @moduledoc """
  What a payment does to a registration: confirming the places a pending
  checkout or invite paid for, recording a balance paid through its link, and
  reconciling a PaymentIntent Stripe never reported.
  """

  use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshStateMachine, AshOban]

  import Ash.Expr, only: [expr: 1]
  import Edenflowers.Actors

  alias Edenflowers.Courses.Validations
  alias Edenflowers.Payments.Changes, as: PaymentChanges
  alias Edenflowers.Payments.Validations, as: PaymentValidations

  oban do
    triggers do
      trigger :reconcile_payment do
        action :reconcile_payment
        queue :default
        max_attempts 1
        lock_for_update? false
        scheduler_cron "*/10 * * * *"
        worker_module_name Edenflowers.Courses.Workers.ReconcilePayment
        scheduler_module_name Edenflowers.Courses.Schedulers.ReconcilePayment
        default_actor system_actor()

        where expr(
                status in [:pending, :confirmed] and not is_nil(payment_intent_id) and
                  updated_at < ago(5, :minute) and updated_at > ago(7, :day)
              )
      end
    end
  end

  actions do
    read :by_payment_link_token do
      argument :token, :string, allow_nil?: false
      get? true
      filter expr(not is_nil(payment_link_token) and payment_link_token == ^arg(:token))

      prepare build(
                load: [
                  :course,
                  :first_name,
                  :paid?,
                  :upcoming?,
                  :seats_held,
                  :total_due,
                  :amount_paid,
                  :amount_held,
                  :balance,
                  :payment_link_open?,
                  :refunded?
                ]
              )
    end

    # Paying at checkout or through an invite's link. Webhook deliveries are
    # at-least-once, so a repeat must not confirm twice. A course that filled
    # up meanwhile still books them: they've paid, and Jennie makes room. So
    # does a payment for other places than the booking now has, revised while
    # it was in flight: the difference is left as a balance for Jennie.
    update :confirm_payment do
      argument :payment_intent_id, :string, allow_nil?: false
      argument :amount_paid, :decimal, allow_nil?: false
      argument :paid_with, :map, default: %{}
      validate Validations.NotAlreadyConfirmed
      validate PaymentValidations.MatchesPaymentIntent
      change transition_state(:confirmed)
      change set_attribute(:confirmed_at, &DateTime.utc_now/0)
      # The PaymentIntent is spent and kept on its Payment. Left here,
      # cancelling the booking would ask Stripe to cancel a paid PaymentIntent.
      change set_attribute(:payment_intent_id, nil)
      change {PaymentChanges.RecordPayment, method: :stripe, amount: :amount_paid}
      change PaymentChanges.ReportAmountMismatch
      change {PaymentChanges.QueueEmail, trigger: :send_confirmation_email}

      require_atomic? false
    end

    # A balance paid through the payment link of a booking already confirmed.
    update :record_link_payment do
      argument :payment_intent_id, :string, allow_nil?: false
      argument :amount_paid, :decimal, allow_nil?: false, constraints: [min: 0, scale: 2]
      argument :paid_with, :map, default: %{}
      change PaymentChanges.ClearPaidPaymentIntent
      change {PaymentChanges.RecordPayment, method: :stripe, amount: :amount_paid}
      change {PaymentChanges.QueueEmail, trigger: :send_payment_received_email, arguments: [amount: :amount_paid]}
      require_atomic? false
    end
  end
end
