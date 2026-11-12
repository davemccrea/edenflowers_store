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
    extensions: [AshStateMachine, AshOban, AshPaperTrail.Resource],
    fragments: [
      Edenflowers.Payments.Payable,
      Edenflowers.Courses.CourseRegistration.Checkout,
      Edenflowers.Courses.CourseRegistration.Customer,
      Edenflowers.Courses.CourseRegistration.Payment,
      Edenflowers.Courses.CourseRegistration.Admin,
      Edenflowers.Courses.CourseRegistration.Emails
    ]

  alias Edenflowers.Accounts.Calculations, as: AccountCalculations
  alias Edenflowers.Events
  alias Edenflowers.Payments.Payment
  alias Edenflowers.ShopTime

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
      transition(:confirm_paid_by_voucher, from: :pending, to: :confirmed)
      transition(:cancel, from: :confirmed, to: :cancelled)
    end
  end

  # The course page's History. Money isn't here: each Payment is its own record.
  paper_trail do
    change_tracking_mode :changes_only
    create_version_on_destroy? false
    store_action_name? true
    ignore_attributes [:inserted_at, :updated_at]
    sensitive_attributes :redact

    # The subject and text Jennie sent in place of the template's, if she rewrote the email.
    metadata :email_subject, :string
    metadata :email_body, :string

    # on_actions only filters updates; an unfinished website checkout isn't a booking yet.
    ignore_actions [:register]

    on_actions [
      :confirm_payment,
      :confirm_paid_by_voucher,
      :open_payment_link,
      :email_payment_link,
      :send_payment_reminder,
      :send_payment_received_email,
      :send_confirmation_email,
      :email_receipt,
      :send_reminder_email,
      :remove_seat,
      :cancel
    ]
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
                     :confirm_paid_by_voucher,
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
    # and the updates only touch one still unpaid.
    policy action([:register, :revise, :add_gift_voucher_with_code, :clear_gift_voucher]) do
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

    publish :confirm_payment, Events.course_registration_paid(:id)
    publish :confirm_paid_by_voucher, Events.course_registration_paid(:id)
    publish :record_link_payment, Events.course_registration_paid(:id)
    # Refreshes the admin's Courses and Overview pages, which have no pull to refresh.
    publish_all :create, Events.admin_bookings()
    publish_all :update, Events.admin_bookings()
    publish_all :destroy, Events.admin_bookings()
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
      description "How Jennie agreed the booking is paid: a payment link or in person. :invoice (bank " <>
                    "transfer) is only on bookings made before it was withdrawn, and is kept so they still read."

      constraints one_of: [:payment_link, :invoice, :on_fulfillment]
      allow_nil? false
      default :on_fulfillment
    end

    attribute :payment_link_token, :string, sensitive?: true
    attribute :payment_link_emailed_at, :utc_datetime
    attribute :confirmed_at, :utc_datetime
    attribute :confirmation_emailed_at, :utc_datetime
    # Why Jennie cancelled, for her own record on the courses page.
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

    has_many :refunds, Edenflowers.Payments.Payment do
      description "The money handed back on the registration that still stands: no Undo, and not undone."
      filter expr(amount < 0 and is_nil(reverses_payment_id) and not exists(reversal, true))
      sort paid_at: :asc
    end
  end

  calculations do
    calculate :match_rank,
              :integer,
              expr(
                fragment(
                  "least(?, ?, ?)",
                  match_rank(name, ^arg(:term)),
                  match_rank(email, ^arg(:term)),
                  match_rank(reference, ^arg(:term))
                )
              ) do
      description "How closely the admin search term matches what a result row shows (see `match_rank`): " <>
                    "0 exact, 1 at the start of a word, 2 elsewhere, 3 for a match in a field the row " <>
                    "doesn't show. The search sorts by it."

      argument :term, :ci_string, allow_nil?: false
    end

    calculate :receipt_available?, :boolean, expr(status == :confirmed and amount_paid > 0) do
      description "Whether the customer can download a receipt for actual money recorded on this booking."
    end

    calculate :first_name, :string, {AccountCalculations.NamePart, source: :name, part: :first} do
      description "A best guess at the first name from the name typed at checkout, for greeting in emails."
    end

    calculate :seats_held, :integer, expr(seats - removed_seats) do
      description "Places the booking still holds: seats bought less those Jennie removed when someone dropped out."
    end

    calculate :seat_removable?, :boolean, expr(status == :confirmed and seats_held > 1) do
      description "Whether Jennie can take one seat off it: confirmed and holding more than one. The last seat " <>
                    "needs a cancel."
    end

    calculate :stripe_payment_intent_id,
              :string,
              fn records, _context ->
                Enum.map(records, fn record ->
                  Enum.find_value(record.payments, & &1.payment_intent_id) || record.payment_intent_id
                end)
              end do
      load [:payment_intent_id, payments: [:payment_intent_id]]

      description "The PaymentIntent to look the booking up by in Stripe: its Payment's once paid, or the " <>
                    "booking's own while a payment is pending. Nil when Stripe was never involved."
    end

    calculate :amount_invoiced, :decimal, expr(0) do
      description "Always 0: a company's course is a private course, invoiced on its own, never a booking."
    end

    calculate :total_due,
              :decimal,
              expr(
                if status == :cancelled,
                  do: kept_amount,
                  else: round(amount * seats_held / seats, 2) + kept_amount
              ) do
      description "The Total due in euros. amount is the price times seats bought, so the seats still held cost " <>
                    "exactly their share of it. Once cancelled, the cancellation charge Jennie kept, paid or not."
    end

    calculate :checkout_total, :decimal, expr(total_due) do
      description "What checkout charges for, in euros: the Total due."
    end

    calculate :committed?, :boolean, expr(status in [:confirmed, :cancelled]) do
      description "Whether places were committed by Jennie or successful website checkout, including cancelled history."
    end

    calculate :refunded_only_by_cancelling?, :boolean, expr(false) do
      description "Whether its money goes back only by cancelling it: never for a course booking."
    end

    calculate :saves_card?, :boolean, expr(false) do
      description "Whether paying for it saves the card for later charges: never for a course booking."
    end

    calculate :cancelled?, :boolean, expr(status == :cancelled) do
      description "Whether Jennie cancelled the confirmed booking. Customers cancel only by asking her."
    end

    calculate :cancellable?, :boolean, expr(status == :confirmed) do
      description "Whether Jennie can cancel it now: a confirmed booking, paid or not."
    end

    calculate :default_cancellation_charge,
              :decimal,
              expr(
                if course.date >= date_add(helsinki_today(), course.cancellation_days, :day) do
                  0
                else
                  round(total_due * course.cancellation_fee_percent / 100, 2)
                end
              ) do
      description "The cancellation charge in euros cancelling now keeps unless Jennie enters another, paid or " <>
                    "not: nothing up to the course's cancellation_days before it, and after that its " <>
                    "cancellation fee on the places still held."
    end

    calculate :cancelled_unsettled?, :boolean, expr(status == :cancelled and not settled?) do
      description "Whether a cancelled booking still needs Jennie: money to refund, a cancellation charge to " <>
                    "collect. The course page lists these beside the live bookings instead " <>
                    "of folding them away with the settled cancellations."
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

    # Computed in Elixir from the loaded balance: as an expression it adds to the Overview's SQL (ADR 0007).
    calculate :payment_overdue?,
              :boolean,
              fn records, _context ->
                overdue_before = Date.add(ShopTime.today(), -Payment.overdue_after_days())

                Enum.map(records, fn record ->
                  Decimal.positive?(record.balance) and Date.compare(record.course.date, overdue_before) == :lt
                end)
              end do
      load [:balance, course: [:date]]
      description "Whether a booking still has a balance more than 14 days after the course."
    end

    calculate :payment_reminder?,
              :boolean,
              expr(status == :confirmed or course.date < helsinki_today()) do
      description "Whether the Payment reminder is available for the accepted booking's Balance."
    end
  end

  identities do
    identity :unique_reference, [:reference]
    identity :unique_payment_link_token, [:payment_link_token]
  end
end
