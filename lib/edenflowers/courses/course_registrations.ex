defmodule Edenflowers.Courses.CourseRegistration do
  use Ash.Resource,
    domain: Edenflowers.Courses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub]

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
      change set_attribute(:status, :pending)
      change {Changes.UpsertUser, []}
      change {Changes.ReserveSeats, []}
    end

    # For people who pay Jennie at the course, so they hold a seat without
    # Stripe. Allowed after online booking closes, but never beyond the
    # course's places.
    create :add_manually do
      accept [:name, :email, :seats, :course_id, :locale]
      validate attribute_in(:locale, @locales)
      change set_attribute(:status, :confirmed)
      change set_attribute(:confirmed_at, &DateTime.utc_now/0)
      change {Changes.UpsertUser, []}
      change {Changes.ReserveSeats, allow_after_cutoff?: true}
    end

    update :add_payment_intent_id do
      accept [:payment_intent_id]
    end

    # Webhook deliveries are at-least-once, so a repeat must not re-confirm.
    # A released hold that still got paid is confirmed anyway: the customer
    # has paid, so they have a place.
    update :confirm_payment do
      validate attribute_does_not_equal(:status, :confirmed)
      change set_attribute(:status, :confirmed)
      change set_attribute(:confirmed_at, &DateTime.utc_now/0)
      require_atomic? false
    end

    # Jennie ticks off manual bookings as people pay at the course.
    # require_atomic? false: see Order.mark_receipt_emailed.
    update :mark_paid do
      validate attribute_equals(:paid_at, nil), message: "already marked as paid"
      change set_attribute(:paid_at, &DateTime.utc_now/0)
      require_atomic? false
    end

    # When someone in a group drops out. Removing the last seat is a cancel.
    # seats and amount stay what was bought, because the receipt is rebuilt
    # from them; a Stripe booking is refunded for the seat in the Stripe dashboard.
    update :remove_seat do
      require_atomic? false

      change fn changeset, _context ->
        %{seats: seats, removed_seats: removed_seats} = changeset.data

        if seats - removed_seats > 1 do
          Ash.Changeset.change_attribute(changeset, :removed_seats, removed_seats + 1)
        else
          Ash.Changeset.add_error(changeset,
            field: :removed_seats,
            message: "cancel the booking to remove its last seat"
          )
        end
      end
    end

    # Jennie refunds in the Stripe dashboard; cancelling here frees the seats.
    update :cancel do
      change set_attribute(:status, :cancelled)
    end

    # require_atomic? false: see Order.mark_receipt_emailed.
    update :mark_receipt_emailed do
      argument :receipt_sha256, :string, allow_nil?: false

      validate attribute_equals(:receipt_emailed_at, nil),
        message: "receipt already marked as emailed"

      change set_attribute(:receipt_emailed_at, &DateTime.utc_now/0)
      change set_attribute(:receipt_sha256, arg(:receipt_sha256))
      require_atomic? false
    end
  end

  policies do
    bypass actor_attribute_equals(:system, true) do
      authorize_if action([:add_payment_intent_id, :confirm_payment, :mark_receipt_emailed, :cancel])
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

    attribute :status, :atom,
      default: :pending,
      constraints: [one_of: [:pending, :confirmed, :cancelled]]

    # Receipt number, from the same generator as order references.
    attribute :reference, :string, allow_nil?: false

    # Snapshotted by ReserveSeats, so a later edit to the course can't change
    # what was charged or what the receipt says.
    attribute :tax_rate, :decimal, allow_nil?: false
    attribute :amount, :decimal, allow_nil?: false

    attribute :payment_intent_id, :string
    attribute :confirmed_at, :utc_datetime
    # Only for manual bookings: a Stripe booking is paid when it is confirmed.
    attribute :paid_at, :utc_datetime
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
