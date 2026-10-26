defmodule Edenflowers.Courses.CourseRegistration.Admin do
  @moduledoc """
   What Jennie does with bookings in the admin: accepting bookings, taking a seat
  back, cancelling, and the list of what is still to settle.
  """

  use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshStateMachine, AshOban]

  import Ash.Expr, only: [expr: 1]
  import Edenflowers.Actors

  alias Edenflowers.Courses.CourseRegistration.Changes
  alias Edenflowers.Payments.Changes, as: PaymentChanges

  @locales Edenflowers.Locales.all()

  oban do
    triggers do
      trigger :send_payment_link_email do
        action :email_payment_link
        queue :default
        max_attempts 3
        lock_for_update? false
        scheduler_cron false
        worker_module_name Edenflowers.Courses.Workers.SendPaymentLinkEmail
        scheduler_module_name Edenflowers.Courses.Schedulers.SendPaymentLinkEmail
        default_actor system_actor()
      end
    end
  end

  actions do
    # What the Overview lists as still to collect or refund.
    read :unsettled do
      description "Confirmed or cancelled bookings with a Balance still to collect or refund, for the admin Overview."
      filter expr(committed? and not settled?)
      prepare build(load: [:balance, :payment_overdue?, :course])
    end

    create :add_manually do
      description "Jennie accepts a booking, including after online cutoff or over capacity. Holds places immediately, " <>
                    "with payment due at the course unless actual received money is entered. Confirmation is optional."

      accept [:name, :email, :seats, :course_id, :locale]
      argument :email_customer?, :boolean, default: true
      argument :message, :string, description: "Jennie's note in the booking confirmation."
      argument :amount, :decimal, constraints: [greater_than: 0, scale: 2]
      argument :payment_method, Edenflowers.Payments.PaymentMethod
      validate present(:payment_method), where: [present(:amount)]
      validate present(:amount), where: [present(:payment_method)]
      validate argument_does_not_equal(:payment_method, :stripe), message: "is recorded from Stripe"
      validate attribute_in(:locale, @locales)
      change Changes.UpsertUser
      change {Changes.PriceBooking, manual?: true}
      change set_attribute(:status, :confirmed)
      change set_attribute(:confirmed_at, &DateTime.utc_now/0)
      change atomic_set(:reference, expr(fragment("nextval('reference_seq')::text")))

      change after_action(fn changeset, registration, context ->
               Ash.update(
                 registration,
                 %{
                   amount: Ash.Changeset.get_argument(changeset, :amount),
                   payment_method: Ash.Changeset.get_argument(changeset, :payment_method)
                 },
                 action: :record_payment,
                 actor: context.actor
               )
             end),
             where: [present(:amount)]

      change {PaymentChanges.QueueEmail, trigger: :send_confirmation_email},
        where: [argument_equals(:email_customer?, true)]
    end

    update :open_payment_link do
      description "Gives a confirmed booking with a Balance a Payment Link, keeping any it has."
      validate attribute_equals(:status, :confirmed), message: "is not confirmed"
      change PaymentChanges.OpenPaymentLink
      require_atomic? false
    end

    # Opens the link if need be, so sending it is opening one.
    update :email_payment_link do
      description "Emails a confirmed booking's Balance collection link, opening it if needed. Jennie sends it explicitly."

      argument :message, :string, description: "Jennie's note in the email."
      validate attribute_equals(:status, :confirmed), message: "is not confirmed"
      change PaymentChanges.OpenPaymentLink
      change Changes.SendPaymentLinkEmail
      transaction? false
      require_atomic? false
    end

    # When someone in a group drops out. Removing the last seat is a cancel.
    # seats and amount stay what was bought, because the receipt is rebuilt
    # from them. Nothing is refunded: the seat's price is left as a negative
    # balance for Jennie to refund.
    update :remove_seat do
      description "Frees one place of a group booking when someone drops out. Refunds nothing: the seat's price " <>
                    "is left as a Balance for Jennie to refund. The last seat needs cancel instead."

      change atomic_update(
               :removed_seats,
               expr(
                 if seats - removed_seats > 1 do
                   removed_seats + 1
                 else
                   error(Ash.Error.Changes.InvalidAttribute, %{
                     field: :removed_seats,
                     message: "cancel the booking to remove its last seat"
                   })
                 end
               )
             )
    end

    # Frees the places. Payments.Changes.Cancel says what happens to the money.
    update :cancel do
      description "Jennie cancels a confirmed booking, freeing its places and refunding all but what she keeps: " <>
                    "card payments through Stripe, the rest left as a Balance. Emails the customer unless told not to."

      accept [:cancellation_reason]

      argument :refund, :decimal,
        constraints: [scale: 2],
        description: "What Jennie chose to refund. Without it, the course's cancellation terms decide."

      argument :held, :decimal,
        constraints: [scale: 2],
        description: "What was held when Jennie opened the cancel form, so a retry never refunds twice."

      argument :email_customer?, :boolean, default: true
      change transition_state(:cancelled)
      change {PaymentChanges.Cancel, cancelled_by: :shop}
      require_atomic? false
    end
  end
end
