defmodule Edenflowers.Courses.CourseRegistration.Status do
  @moduledoc """
  The states of a course registration. Pending isn't a booking yet: someone
  paying at checkout, or someone Jennie invited with a payment link. Paying
  confirms it, and only a confirmed booking holds places.
  """

  use Ash.Type.Enum, values: [:pending, :confirmed, :cancelled]
end

defmodule Edenflowers.Courses.CourseRegistration do
  @moduledoc """
  A course registration and its payment state. A place is booked only once
  it is paid: a pending registration holds nothing, and is deleted rather
  than cancelled when it's given up. A confirmed booking may be cancelled or
  refunded.
  """

  use Ash.Resource,
    domain: Edenflowers.Courses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshStateMachine, AshOban],
    fragments: [Edenflowers.Payments.Payable]

  import Edenflowers.Actors

  alias Edenflowers.Accounts.Calculations, as: AccountCalculations
  alias Edenflowers.Courses.Changes
  alias Edenflowers.Courses.Validations
  alias Edenflowers.Payments.Changes, as: PaymentChanges
  alias Edenflowers.Payments.Payment
  alias Edenflowers.Payments.Validations, as: PaymentValidations

  @locales Edenflowers.Locales.all()

  # Enough for the usual group of friends without letting one booking empty a course.
  @max_seats 4

  def max_seats, do: @max_seats

  postgres do
    repo Edenflowers.Repo
    table "course_registrations"
    migration_types amount: :decimal, kept_amount: :decimal

    check_constraints do
      check_constraint :amount, "course_registrations_valid_amount",
        check: "amount >= 0 AND amount = round(amount, 2)",
        message: "must be a non-negative amount in whole cents"
    end
  end

  state_machine do
    state_attribute(:status)
    initial_states([:pending])
    default_initial_state(:pending)

    transitions do
      transition(:confirm_payment, from: :pending, to: :confirmed)
      transition(:cancel, from: :confirmed, to: :cancelled)
    end
  end

  oban do
    triggers do
      trigger :send_confirmation_email do
        action :send_confirmation_email
        queue :default
        max_attempts 3
        lock_for_update? false
        scheduler_cron false
        worker_module_name Edenflowers.Courses.Workers.SendConfirmationEmail
        scheduler_module_name Edenflowers.Courses.Schedulers.SendConfirmationEmail
        default_actor system_actor()
      end

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

      trigger :send_payment_received_email do
        action :send_payment_received_email
        queue :default
        max_attempts 3
        lock_for_update? false
        scheduler_cron false
        worker_module_name Edenflowers.Courses.Workers.SendPaymentReceivedEmail
        scheduler_module_name Edenflowers.Courses.Schedulers.SendPaymentReceivedEmail
        default_actor system_actor()
      end

      # Once a day, the day before the course. The stamp makes it one each.
      trigger :send_reminder_email do
        action :send_reminder_email
        queue :default
        max_attempts 3
        lock_for_update? false
        scheduler_cron "0 7 * * *"
        worker_module_name Edenflowers.Courses.Workers.SendReminderEmail
        scheduler_module_name Edenflowers.Courses.Schedulers.SendReminderEmail
        default_actor system_actor()

        where expr(
                status == :confirmed and is_nil(reminder_emailed_at) and
                  course.date == date_add(helsinki_today(), 1, :day)
              )
      end

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
    defaults [:read]

    # Same reason as Order.mine: the admin bypass below grants an unrestricted
    # read, so the customer-facing list narrows itself with a filter.
    read :mine do
      filter expr(user_id == ^actor(:id) and status == :confirmed)
    end

    # What the Overview lists as still to collect or refund.
    read :unsettled do
      filter expr(committed? and not settled?)
      prepare build(load: [:balance, :payment_overdue?, :course])
    end

    # What its cancelled and refunded emails need.
    read :for_customer_email do
      prepare build(load: [:course, :first_name, :payments])
    end

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

    # The checkout a customer is paying for on the course page, so a failed
    # payment's return can pick it up again.
    read :checkout do
      get? true
      filter expr(status == :pending and is_nil(payment_link_token))
    end

    create :register do
      accept [:name, :email, :seats, :course_id, :locale]
      validate attribute_in(:locale, @locales)
      change Changes.UpsertUser
      change Changes.PriceBooking
      change atomic_set(:reference, expr(fragment("nextval('reference_seq')::text")))
    end

    # Going back at checkout keeps the registration, and the PaymentIntent it
    # may already have, which is brought up to the new price before paying.
    # The filter refuses a booking confirmed meanwhile at the database: a
    # payment that wins books what was registered when it landed.
    update :revise do
      accept [:name, :email, :seats]
      change filter expr(status == :pending and is_nil(payment_link_token))
      change Changes.UpsertUser
      change Changes.PriceBooking
      require_atomic? false
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

    # Sent by hand only, like the order's. Opens the link if need be.
    update :send_payment_reminder do
      argument :message, :string
      validate attribute_equals(:status, :confirmed), message: "is not confirmed"
      change PaymentChanges.OpenPaymentLink
      change {Changes.SendPaymentLinkEmail, email: :payment_reminder}
      transaction? false
      require_atomic? false
    end

    update :send_payment_received_email do
      accept []
      argument :amount, :decimal
      argument :message, :string
      transaction? false
      require_atomic? false
      change PaymentChanges.SendPaymentReceivedEmail
    end

    update :send_confirmation_email do
      accept []
      argument :message, :string
      transaction? false
      require_atomic? false
      change Changes.SendConfirmationEmail
    end

    update :send_reminder_email do
      accept []
      transaction? false
      require_atomic? false
      change Changes.SendReminderEmail
    end

    # The confirmation again, with its receipt.
    update :email_receipt do
      accept []
      argument :message, :string
      validate attribute_equals(:status, :confirmed), message: "is not confirmed"
      transaction? false
      require_atomic? false
      change Changes.SendConfirmationEmail
    end
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if action([
                     :add_payment_intent_id,
                     :mark_payment_cancelled,
                     :confirm_payment,
                     :record_link_payment,
                     :record_stripe_refund,
                     :send_confirmation_email,
                     :email_payment_link,
                     :send_payment_received_email,
                     :send_reminder_email,
                     :reconcile_payment,
                     :discard,
                     :checkout
                   ])

      authorize_if action_type(:read)
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # A checkout is reached by its unguessable id, as the bookings page is,
    # and :revise only touches one still unpaid.
    policy action([:register, :revise]) do
      authorize_if always()
    end

    # Every registration is linked to the user with its email, so a customer
    # sees their bookings, guest or not, once that email signs in. Past
    # checkout, payment confirms it and only Jennie changes it.
    policy action_type(:read) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  pub_sub do
    module EdenflowersWeb.Endpoint

    publish :confirm_payment, ["course_registration", "paid", :id]
    publish :record_link_payment, ["course_registration", "paid", :id]
    # Refreshes the admin's Courses and Overview pages, which have no pull to refresh.
    publish_all :create, ["admin", "bookings"]
    publish_all :update, ["admin", "bookings"]
    publish_all :destroy, ["admin", "bookings"]
  end

  validations do
    # Courses are paid by payment link, never in person.
    validate negate(action_is(:record_payment)), message: "is paid by payment link"
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, constraints: [trim?: true, min_length: 1]
    attribute :email, Edenflowers.Types.Email, allow_nil?: false
    # Seats bought, as on the receipt. Seats held is seats minus removed_seats.
    attribute :seats, :integer, allow_nil?: false, default: 1, constraints: [min: 1, max: @max_seats]
    attribute :removed_seats, :integer, allow_nil?: false, default: 0, constraints: [min: 0]
    attribute :locale, :string, allow_nil?: false, default: "sv-FI"

    attribute :status, __MODULE__.Status, allow_nil?: false, default: :pending

    # Receipt number, from the same sequence as order references.
    attribute :reference, :string, allow_nil?: false

    # Snapshotted by PriceBooking, so a later edit to the course can't change
    # what was charged or what the receipt says.
    attribute :tax_rate, :decimal, allow_nil?: false
    attribute :amount, :decimal, allow_nil?: false, constraints: [min: 0, scale: 2]

    attribute :payment_intent_id, :string
    attribute :payment_link_token, :string, sensitive?: true
    attribute :payment_link_emailed_at, :utc_datetime
    attribute :confirmed_at, :utc_datetime
    attribute :confirmation_emailed_at, :utc_datetime
    # Why Jennie cancelled, for the customer's email and the courses page.
    attribute :cancellation_reason, :string
    attribute :cancelled_at, :utc_datetime
    # The customer's email can change later; this names who was told.
    attribute :cancellation_emailed_to, :string
    attribute :receipt_emailed_at, :utc_datetime
    attribute :reminder_emailed_at, :utc_datetime

    timestamps()
  end

  relationships do
    belongs_to :user, Edenflowers.Accounts.User do
      allow_nil? true
    end

    belongs_to :course, Edenflowers.Courses.Course, allow_nil?: false

    has_many :payments, Edenflowers.Payments.Payment do
      sort paid_at: :asc
    end
  end

  calculations do
    calculate :first_name, :string, {AccountCalculations.FirstName, source: :name}

    calculate :seats_held, :integer, expr(seats - removed_seats)

    # amount is the price times seats bought, so the seats still held cost
    # exactly their share of it.
    calculate :total_due,
              :decimal,
              expr(if status == :cancelled, do: kept_amount, else: round(amount * seats_held / seats, 2) + kept_amount)

    # Nothing is owed on a registration until it is paid for, so only a
    # confirmed or cancelled booking is committed.
    calculate :committed?, :boolean, expr(status in [:confirmed, :cancelled])
    calculate :cancelled?, :boolean, expr(status == :cancelled)
    calculate :cancellable?, :boolean, expr(status == :confirmed)

    # Everything held before the course's cancellation deadline, and after it
    # all but the course's fee.
    calculate :refund_on_cancelling,
              :decimal,
              expr(
                cond do
                  amount_held <= 0 ->
                    0

                  course.date >= date_add(helsinki_today(), course.cancellation_days, :day) ->
                    amount_held

                  amount_held > round(amount * course.cancellation_fee_percent / 100, 2) ->
                    amount_held - round(amount * course.cancellation_fee_percent / 100, 2)

                  true ->
                    0
                end
              )

    calculate :customer_email, :string, expr(email)
    calculate :paid?, :boolean, expr(status == :confirmed and not refunded? and balance <= 0)
    calculate :upcoming?, :boolean, expr(status == :confirmed and seats_held > 0 and not course.ended?)

    calculate :payment_overdue?,
              :boolean,
              expr(
                balance > 0 and
                  course.date < date_add(helsinki_today(), ^(-Payment.overdue_after_days()), :day)
              )

    calculate :payment_link_open?,
              :boolean,
              expr(not is_nil(payment_link_token) and payable? and status in [:pending, :confirmed])
  end

  identities do
    identity :unique_reference, [:reference]
    identity :unique_payment_link_token, [:payment_link_token]
  end
end
