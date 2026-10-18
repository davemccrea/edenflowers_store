defmodule Edenflowers.Courses.CourseRegistration.Status do
  use Ash.Type.Enum, values: [:pending, :confirmed, :cancelled]
end

defmodule Edenflowers.Courses.CourseRegistration do
  use Ash.Resource,
    domain: Edenflowers.Courses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshOban],
    fragments: [Edenflowers.Payments.Payable]

  import Edenflowers.Actors

  alias Edenflowers.Accounts.Calculations, as: AccountCalculations
  alias Edenflowers.Courses.Changes
  alias Edenflowers.Courses.Validations
  alias Edenflowers.Payments.Changes, as: PaymentChanges
  alias Edenflowers.Payments.Validations, as: PaymentValidations

  @locales Edenflowers.Locales.all()

  # How long a pending booking holds its seats while the customer pays.
  @hold_minutes 10

  # Enough for the usual group of friends without letting one booking empty a course.
  @max_seats 4

  def max_seats, do: @max_seats

  postgres do
    repo Edenflowers.Repo
    table "course_registrations"
    migration_types amount: :decimal

    check_constraints do
      check_constraint :amount, "course_registrations_valid_amount",
        check: "amount >= 0 AND amount = round(amount, 2)",
        message: "must be a non-negative amount in whole cents"
    end
  end

  oban do
    triggers do
      trigger :send_confirmation_email do
        action :send_confirmation_email
        queue :default
        max_attempts 20
        lock_for_update? false
        scheduler_cron "*/10 * * * *"
        worker_module_name Edenflowers.Courses.Workers.SendConfirmationEmail
        scheduler_module_name Edenflowers.Courses.Schedulers.SendConfirmationEmail
        default_actor system_actor()
        where expr(status == :confirmed and is_nil(confirmation_emailed_at))
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
                status == :pending and not is_nil(payment_intent_id) and
                  updated_at < ago(5, :minute) and updated_at > ago(7, :day)
              )
      end
    end
  end

  actions do
    defaults [:read, :destroy]

    # Same reason as Order.mine: the admin bypass below grants an unrestricted
    # read, so the customer-facing list narrows itself with a filter. The plain
    # :read stays unscoped because Course.seats_taken counts through it.
    read :mine do
      filter expr(user_id == ^actor(:id) and status == :confirmed)
    end

    # What the Overview lists as still to collect or refund.
    read :unsettled do
      filter expr(committed? and not settled?)
      prepare build(load: [:balance, :course])
    end

    read :by_payment_link_token do
      argument :token, :string, allow_nil?: false
      get? true
      filter expr(not is_nil(payment_link_token) and payment_link_token == ^arg(:token))
      prepare build(load: [:course, :seats_held, :total_due, :amount_paid, :balance, :payment_link_open?])
    end

    create :register do
      accept [:name, :email, :seats, :course_id, :locale]
      validate attribute_in(:locale, @locales)
      change set_attribute(:status, :pending)
      change Changes.UpsertUser
      change Changes.ReserveSeats
      change atomic_set(:reference, expr(fragment("nextval('reference_seq')::text")))
    end

    # For people who pay Jennie at the course, so they hold a seat without
    # Stripe. Allowed after online booking closes, but never beyond the
    # course's places.
    create :add_manually do
      accept [:name, :email, :seats, :course_id, :locale]
      validate attribute_in(:locale, @locales)
      change set_attribute(:status, :confirmed)
      change set_attribute(:confirmed_at, &DateTime.utc_now/0)
      change Changes.UpsertUser
      change {Changes.ReserveSeats, allow_after_cutoff?: true}
      change atomic_set(:reference, expr(fragment("nextval('reference_seq')::text")))
      change PaymentChanges.ScheduleConfirmationEmail
    end

    update :add_payment_intent_id do
      accept [:payment_intent_id]
      validate PaymentValidations.PaymentIntentNotSet
    end

    update :mark_payment_cancelled do
      argument :payment_intent_id, :string, allow_nil?: false
      validate PaymentValidations.MatchesPaymentIntent
      change set_attribute(:payment_intent_id, nil)
    end

    # Webhook deliveries are at-least-once, so a repeat must not re-confirm.
    # A released hold that still got paid is confirmed anyway: the customer
    # has paid, so they have a place.
    update :confirm_payment do
      argument :payment_intent_id, :string, allow_nil?: false
      argument :amount_paid, :decimal, allow_nil?: false
      argument :paid_with, :map, default: %{}
      validate Validations.NotAlreadyConfirmed
      validate PaymentValidations.MatchesPaymentIntent
      validate Validations.MatchesPaymentAmount
      change set_attribute(:status, :confirmed)
      change set_attribute(:confirmed_at, &DateTime.utc_now/0)
      # The PaymentIntent is spent and kept on its Payment. Left here,
      # cancelling the booking would ask Stripe to cancel a paid PaymentIntent.
      change set_attribute(:payment_intent_id, nil)
      change {PaymentChanges.RecordPayment, method: :stripe, amount: :amount_paid}
      change PaymentChanges.ScheduleConfirmationEmail

      require_atomic? false
    end

    # A payment through the payment link on a booking already confirmed, so
    # unlike confirm_payment this only records what arrived.
    update :record_link_payment do
      argument :payment_intent_id, :string, allow_nil?: false
      argument :amount_paid, :decimal, allow_nil?: false, constraints: [min: 0, scale: 2]
      argument :paid_with, :map, default: %{}
      # One Jennie dropped by recording a payment can still be paid, and that
      # money has arrived all the same. Only the PaymentIntent paid stops being open.
      change fn changeset, _context ->
        if changeset.data.payment_intent_id == Ash.Changeset.get_argument(changeset, :payment_intent_id),
          do: Ash.Changeset.force_change_attribute(changeset, :payment_intent_id, nil),
          else: changeset
      end

      # The confirmation goes out again, now with the receipt.
      change set_attribute(:confirmation_emailed_at, nil)
      change {PaymentChanges.RecordPayment, method: :stripe, amount: :amount_paid}
      change PaymentChanges.ScheduleConfirmationEmail
      require_atomic? false
    end

    # Only a confirmed booking owes money; a pending one pays at checkout.
    update :open_payment_link do
      validate attribute_equals(:status, :confirmed), message: "is not confirmed"
      change PaymentChanges.OpenPaymentLink
      require_atomic? false
    end

    # Opens the link if need be, so sending it is opening one.
    update :email_payment_link do
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

    # Frees the seats and leaves what was paid as a negative balance for
    # Jennie to refund.
    update :cancel do
      change set_attribute(:status, :cancelled)
      change PaymentChanges.CancelOpenPaymentIntent
      require_atomic? false
    end

    update :send_confirmation_email do
      accept []
      transaction? false
      require_atomic? false
      change Changes.SendConfirmationEmail
    end

    update :reconcile_payment do
      accept []
      transaction? false
      require_atomic? false
      change PaymentChanges.Reconcile
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
                     :reconcile_payment,
                     :cancel
                   ])

      authorize_if action_type(:read)
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy action(:register) do
      authorize_if always()
    end

    # Every registration is linked to the user with its email, so a customer
    # sees their bookings, guest or not, once that email signs in.
    # Customers never update a registration: payment confirms it.
    policy action_type(:read) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  pub_sub do
    module EdenflowersWeb.Endpoint

    publish :record_link_payment, ["course_registration", "paid", :id]
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

    # Snapshotted by ReserveSeats, so a later edit to the course can't change
    # what was charged or what the receipt says.
    attribute :tax_rate, :decimal, allow_nil?: false
    attribute :amount, :decimal, allow_nil?: false, constraints: [min: 0, scale: 2]

    attribute :payment_intent_id, :string
    attribute :payment_link_token, :string, sensitive?: true
    attribute :payment_link_emailed_at, :utc_datetime
    attribute :confirmed_at, :utc_datetime
    attribute :confirmation_emailed_at, :utc_datetime
    attribute :receipt_emailed_at, :utc_datetime
    attribute :receipt_sha256, :string

    timestamps()
  end

  relationships do
    belongs_to :user, Edenflowers.Accounts.User do
      allow_nil? true
    end

    belongs_to :course, Edenflowers.Courses.Course, allow_nil?: false
    has_many :payments, Edenflowers.Payments.Payment
  end

  calculations do
    calculate :first_name, :string, {AccountCalculations.FirstName, source: :name}

    calculate :seats_held, :integer, expr(seats - removed_seats)

    # amount is the price times seats bought, so the seats still held cost
    # exactly their share of it.
    calculate :total_due,
              :decimal,
              expr(if status == :cancelled, do: 0, else: round(amount * seats_held / seats, 2))

    # A pending booking only holds its seats while the customer pays.
    calculate :committed?, :boolean, expr(status in [:confirmed, :cancelled])

    calculate :holds_seats?,
              :boolean,
              expr(status == :confirmed or (status == :pending and inserted_at > ago(@hold_minutes, :minute)))

    calculate :payment_link_open?,
              :boolean,
              expr(not is_nil(payment_link_token) and balance > 0 and status == :confirmed)
  end

  identities do
    identity :unique_reference, [:reference]
    identity :unique_payment_link_token, [:payment_link_token]
  end
end
