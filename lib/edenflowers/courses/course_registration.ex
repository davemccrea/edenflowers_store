defmodule Edenflowers.Courses.CourseRegistration.Status do
  @moduledoc """
  Pending is unfinished website checkout and holds no places. Confirmed is a
  commitment to provide places, accepted by Jennie or by successful checkout,
  regardless of whether money is still owed. Cancelled frees the places.
  """

  use Ash.Type.Enum, values: [:pending, :confirmed, :cancelled]
end

defmodule Edenflowers.Courses.CourseRegistration do
  @moduledoc """
  A retained course registration and its booking commitment. Website checkout
  stays pending until paid; Jennie's manual bookings are confirmed immediately.
  Payment rows separately record money received or returned. Cancellation frees
  places without deleting their history or preventing late money being recorded.

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
    initial_states([:pending, :confirmed])
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

    attribute :payment_terms, :atom do
      constraints one_of: [:payment_link, :invoice, :on_fulfillment]
      allow_nil? false
      default :on_fulfillment
    end

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
      description "The account with the registration's email, guest or not, so the customer sees their bookings " <>
                    "once that email signs in."

      allow_nil? true
    end

    belongs_to :course, Edenflowers.Courses.Course do
      description "The course the places are on."
      allow_nil? false
    end

    has_many :payments, Edenflowers.Payments.Payment do
      description "Every Payment and refund on the registration, oldest first."
      sort paid_at: :asc
    end
  end

  calculations do
    calculate :receipt_available?, :boolean, expr(status == :confirmed and amount_paid > 0) do
      description "Whether the customer can download a receipt for actual money recorded on this booking."
    end

    calculate :first_name, :string, {AccountCalculations.FirstName, source: :name} do
      description "A best guess at the first name from the name typed at checkout, for greeting in emails."
    end

    calculate :seats_held, :integer, expr(seats - removed_seats) do
      description "Places the booking still holds: seats bought less those Jennie removed when someone dropped out."
    end

    calculate :total_due,
              :decimal,
              expr(
                if status == :cancelled,
                  do: kept_amount,
                  else: round(amount * seats_held / seats, 2) + kept_amount
              ) do
      description "The Total due in euros. amount is the price times seats bought, so the seats still held cost " <>
                    "exactly their share of it. Once cancelled, only what Jennie kept."
    end

    calculate :committed?, :boolean, expr(status in [:confirmed, :cancelled]) do
      description "Whether places were committed by Jennie or successful website checkout, including cancelled history."
    end

    calculate :cancelled?, :boolean, expr(status == :cancelled) do
      description "Whether Jennie cancelled the confirmed booking. Customers cancel only by asking her."
    end

    calculate :cancellable?, :boolean, expr(status == :confirmed) do
      description "Whether Jennie can cancel it now: a confirmed booking, paid or not."
    end

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
              ) do
      description "What cancelling now refunds in euros unless Jennie says otherwise: everything held up to the " <>
                    "course's cancellation_days before it, and after that all but its cancellation fee."
    end

    calculate :customer_email, :string, expr(email) do
      description "Who is told about cancels and refunds: the email given at checkout or entered by Jennie."
    end

    calculate :paid?, :boolean, expr(status == :confirmed and not refunded? and balance <= 0) do
      description "Whether a confirmed booking has nothing left to pay and wasn't refunded, for its Payment Link page."
    end

    calculate :upcoming?, :boolean, expr(status == :confirmed and seats_held > 0 and not course.ended?) do
      description "Whether a confirmed booking still holds places on a course that hasn't ended."
    end

    calculate :payment_overdue?,
              :boolean,
              expr(
                balance > 0 and
                  course.date < date_add(helsinki_today(), ^(-Payment.overdue_after_days()), :day)
              ) do
      description "Whether a Balance is still to collect more than 14 days after the course, the usual " <>
                    "Finnish invoice term, counted in Helsinki days."
    end

    calculate :payment_reminder?,
              :boolean,
              expr(status == :confirmed or course.date < helsinki_today()) do
      description "Whether the Payment reminder is available for the accepted booking's Balance."
    end

    calculate :payment_link_open?,
              :boolean,
              expr(not is_nil(payment_link_token) and payable? and status in [:pending, :confirmed]) do
      description "Whether its Payment Link would take a payment now: it has one, something is payable, and it " <>
                    "isn't cancelled."
    end
  end

  identities do
    identity :unique_reference, [:reference]
    identity :unique_payment_link_token, [:payment_link_token]
  end
end
