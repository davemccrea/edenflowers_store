defmodule Edenflowers.Courses.CourseRegistration.Admin do
  @moduledoc """
  What Jennie does with bookings in the admin: inviting people, taking a seat
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
      # Queued when Jennie invites someone and ticks "email the customer".
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

      # A checkout the customer walked away from. An invite stays until Jennie
      # withdraws it.
      trigger :discard_abandoned do
        action :discard
        queue :default
        max_attempts 1
        lock_for_update? false
        scheduler_cron "0 3 * * *"
        worker_module_name Edenflowers.Courses.Workers.DiscardAbandoned
        scheduler_module_name Edenflowers.Courses.Schedulers.DiscardAbandoned
        default_actor system_actor()
        where expr(status == :pending and is_nil(payment_link_token) and updated_at < ago(1, :day))
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

    # Someone Jennie invites to book, with a payment link, even after online
    # booking closes. It holds no places: paying the link books them.
    create :add_manually do
      description "Jennie sends an Invite: a pending registration with a Payment Link, allowed after online " <>
                    "booking closes. Holds no places until paid, and emails the link unless told not to."

      accept [:name, :email, :seats, :course_id, :locale]
      argument :email_customer?, :boolean, default: true
      argument :message, :string, description: "Jennie's note in the payment link email."
      validate attribute_in(:locale, @locales)
      change Changes.UpsertUser
      change {Changes.PriceBooking, allow_after_cutoff?: true}
      change atomic_set(:reference, expr(fragment("nextval('reference_seq')::text")))
      change PaymentChanges.OpenPaymentLink

      change {PaymentChanges.QueueEmail, trigger: :send_payment_link_email},
        where: [argument_equals(:email_customer?, true)]
    end

    # An invite's link, or a balance left on a confirmed booking. A checkout
    # pays on the course page instead.
    update :open_payment_link do
      description "Gives an Invite, or a confirmed booking with a Balance, a Payment Link, keeping any it has."
      validate attribute_in(:status, [:pending, :confirmed]), message: "is cancelled"
      change PaymentChanges.OpenPaymentLink
      require_atomic? false
    end

    # Opens the link if need be, so sending it is opening one.
    update :email_payment_link do
      description "Emails the customer the Payment Link of an Invite or confirmed booking, opening it if need be. " <>
                    "Jennie sends it, or add_manually queues it."

      argument :message, :string, description: "Jennie's note in the email."
      validate attribute_in(:status, [:pending, :confirmed]), message: "is cancelled"
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

    # A registration nobody paid for: a checkout changed or given up, or an
    # invite Jennie withdraws. Its PaymentIntent is cancelled first, so a
    # payment already under way still has a registration to confirm.
    destroy :discard do
      description "Deletes an unpaid pending registration, an abandoned checkout or a withdrawn Invite, after " <>
                    "cancelling its PaymentIntent. Runs nightly for checkouts left a day."

      change filter expr(status == :pending)
      change {PaymentChanges.CancelOpenPaymentIntent, before_commit?: true}
      require_atomic? false
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
