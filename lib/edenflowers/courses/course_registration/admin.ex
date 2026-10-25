defmodule Edenflowers.Courses.CourseRegistration.Admin do
  @moduledoc """
  What Jennie does with bookings in the admin: inviting people, taking a seat
  back, cancelling, and the list of what is still to settle.
  """

  use Spark.Dsl.Fragment, of: Ash.Resource, extensions: [AshStateMachine, AshOban]

  import Ash.Expr, only: [expr: 1]
  import Edenflowers.Actors

  alias Edenflowers.Courses.Changes
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
      filter expr(committed? and not settled?)
      prepare build(load: [:balance, :payment_overdue?, :course])
    end

    # Someone Jennie invites to book, with a payment link, even after online
    # booking closes. It holds no places: paying the link books them.
    create :add_manually do
      accept [:name, :email, :seats, :course_id, :locale]
      argument :email_customer?, :boolean, default: true
      argument :message, :string
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
      validate attribute_in(:status, [:pending, :confirmed]), message: "is cancelled"
      change PaymentChanges.OpenPaymentLink
      require_atomic? false
    end

    # Opens the link if need be, so sending it is opening one.
    update :email_payment_link do
      argument :message, :string
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
      change filter expr(status == :pending)
      change {PaymentChanges.CancelOpenPaymentIntent, before_commit?: true}
      require_atomic? false
    end

    # Frees the places. Payments.Changes.Cancel says what happens to the money.
    update :cancel do
      accept [:cancellation_reason]
      argument :refund, :decimal, constraints: [scale: 2]
      argument :held, :decimal, constraints: [scale: 2]
      argument :email_customer?, :boolean, default: true
      change transition_state(:cancelled)
      change {PaymentChanges.Cancel, cancelled_by: :shop}
      require_atomic? false
    end
  end
end
