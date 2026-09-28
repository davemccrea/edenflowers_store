defmodule Edenflowers.Courses.CourseRegistration.Status do
  use Ash.Type.Enum, values: [:pending, :confirmed, :cancelled]
end

defmodule Edenflowers.Courses.CourseRegistration do
  use Ash.Resource,
    domain: Edenflowers.Courses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshOban]

  alias Edenflowers.Courses.CourseRegistration.Changes

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
        worker_module_name Edenflowers.Courses.CourseRegistration.Workers.SendConfirmationEmail
        scheduler_module_name Edenflowers.Courses.CourseRegistration.Schedulers.SendConfirmationEmail
        default_actor Edenflowers.Actors.system_actor()
        where expr(status == :confirmed and is_nil(confirmation_emailed_at))
      end

      trigger :reconcile_payment do
        action :reconcile_payment
        queue :default
        max_attempts 1
        lock_for_update? false
        scheduler_cron "*/10 * * * *"
        worker_module_name Edenflowers.Courses.CourseRegistration.Workers.ReconcilePayment
        scheduler_module_name Edenflowers.Courses.CourseRegistration.Schedulers.ReconcilePayment
        default_actor Edenflowers.Actors.system_actor()

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

    create :register do
      accept [:name, :email, :seats, :course_id, :locale]
      validate attribute_in(:locale, @locales)
      validate match(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/), message: "Must be a valid email address"
      change set_attribute(:status, :pending)
      change Changes.UpsertUser
      change Changes.ReserveSeats
    end

    # For people who pay Jennie at the course, so they hold a seat without
    # Stripe. Allowed after online booking closes, but never beyond the
    # course's places.
    create :add_manually do
      accept [:name, :email, :seats, :course_id, :locale]
      validate attribute_in(:locale, @locales)
      validate match(:email, ~r/^[^\s@]+@[^\s@]+\.[^\s@]+$/), message: "Must be a valid email address"
      change set_attribute(:status, :confirmed)
      change set_attribute(:confirmed_at, &DateTime.utc_now/0)
      change Changes.UpsertUser
      change {Changes.ReserveSeats, allow_after_cutoff?: true}
      change Edenflowers.Payments.Changes.ScheduleConfirmationEmail
    end

    update :add_payment_intent_id do
      accept [:payment_intent_id]
      validate Edenflowers.Payments.Validations.PaymentIntentNotSet
    end

    # Webhook deliveries are at-least-once, so a repeat must not re-confirm.
    # A released hold that still got paid is confirmed anyway: the customer
    # has paid, so they have a place.
    update :confirm_payment do
      argument :payment_intent_id, :string, allow_nil?: false
      argument :amount_paid, :decimal, allow_nil?: false
      validate {Edenflowers.Payments.Validations.NotAlreadyPaid, attribute: :status, paid: :confirmed}
      validate Edenflowers.Payments.Validations.MatchesPaymentIntent
      validate Edenflowers.Courses.CourseRegistration.Validations.MatchesPaymentAmount
      change set_attribute(:status, :confirmed)
      change set_attribute(:confirmed_at, &DateTime.utc_now/0)
      change Edenflowers.Payments.Changes.ScheduleConfirmationEmail

      require_atomic? false
    end

    # Jennie ticks off manual bookings as people pay at the course.
    update :mark_paid do
      validate absent(:paid_at), message: "already marked as paid"
      change set_attribute(:paid_at, &DateTime.utc_now/0)
    end

    # When someone in a group drops out. Removing the last seat is a cancel.
    # seats and amount stay what was bought, because the receipt is rebuilt
    # from them; a Stripe booking is refunded for the seat in the Stripe dashboard.
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

    # Jennie refunds in the Stripe dashboard; cancelling here frees the seats.
    update :cancel do
      change set_attribute(:status, :cancelled)
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
      change Edenflowers.Payments.Changes.Reconcile
    end
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if action([
                     :add_payment_intent_id,
                     :confirm_payment,
                     :send_confirmation_email,
                     :reconcile_payment,
                     :cancel
                   ])

      authorize_if action_type(:read)
    end

    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Anyone can register (for the guest registration flow).
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

    publish :confirm_payment, ["course_registration", "confirmed", :id]
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false, constraints: [trim?: true, min_length: 1]
    attribute :email, :string, allow_nil?: false, constraints: [trim?: true, min_length: 1]
    # Seats bought, as on the receipt. Seats held is seats minus removed_seats.
    attribute :seats, :integer, allow_nil?: false, default: 1, constraints: [min: 1, max: @max_seats]
    attribute :removed_seats, :integer, allow_nil?: false, default: 0, constraints: [min: 0]
    attribute :locale, :string, allow_nil?: false, default: "sv-FI"

    attribute :status, __MODULE__.Status, allow_nil?: false, default: :pending

    # Receipt number, from the same generator as order references.
    attribute :reference, :string, allow_nil?: false

    # Snapshotted by ReserveSeats, so a later edit to the course can't change
    # what was charged or what the receipt says.
    attribute :tax_rate, :decimal, allow_nil?: false
    attribute :amount, :decimal, allow_nil?: false, constraints: [min: 0, scale: 2]

    attribute :payment_intent_id, :string
    attribute :confirmed_at, :utc_datetime
    # Only for manual bookings: a Stripe booking is paid when it is confirmed.
    attribute :paid_at, :utc_datetime
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
  end

  calculations do
    calculate :first_name, :string, {Edenflowers.Accounts.Calculations.FirstName, source: :name}

    calculate :pays_at_course?, :boolean, expr(is_nil(payment_intent_id) and is_nil(paid_at))

    calculate :seats_held, :integer, expr(seats - removed_seats)

    calculate :holds_seats?,
              :boolean,
              expr(status == :confirmed or (status == :pending and inserted_at > ago(@hold_minutes, :minute)))
  end
end
