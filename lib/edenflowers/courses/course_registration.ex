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

  This file holds what every registration shares: its fields, lifecycle,
  policies and calculations. The actions live in fragments under
  `course_registration/`, one for each side of the course that uses them.
  Policies stay here, so who may do what reads in one place.
  """

  use Ash.Resource,
    domain: Edenflowers.Courses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshStateMachine, AshOban],
    fragments: [
      Edenflowers.Payments.Payable,
      Edenflowers.Courses.CourseRegistration.Checkout,
      Edenflowers.Courses.CourseRegistration.Customer,
      Edenflowers.Courses.CourseRegistration.Payment,
      Edenflowers.Courses.CourseRegistration.Admin,
      Edenflowers.Courses.CourseRegistration.Emails
    ]

  alias Edenflowers.Accounts.Calculations, as: AccountCalculations
  alias Edenflowers.Payments.Payment

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

  actions do
    defaults [:read]
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

    # Each reads the registration with the access it needs itself: a checkout
    # by its id, a link by its token.
    policy action([:prepare_checkout_payment, :prepare_link_payment]) do
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
