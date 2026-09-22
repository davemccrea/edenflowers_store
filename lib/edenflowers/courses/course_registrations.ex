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
      change {Changes.SetUserFromActor, []}
      change {Changes.ReserveSeats, []}
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

    # Anyone can create registrations (for the guest registration flow).
    policy action_type(:create) do
      authorize_if always()
    end

    # Guest registrations have a nil user_id, so this expr only ever matches
    # a logged-in user's own rows. Guest rows stay admin-only via the bypass.
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
    attribute :seats, :integer, allow_nil?: false, default: 1, constraints: [min: 1, max: @max_seats]
    attribute :locale, :string, allow_nil?: false, default: "sv-FI"

    attribute :status, :atom,
      default: :pending,
      constraints: [one_of: [:pending, :confirmed, :cancelled]]

    # Receipt number, from the same generator as order references.
    attribute :reference, :string, allow_nil?: false

    # Snapshotted by ReserveSeats, so a later edit to the course can't change
    # what was charged or what the receipt says.
    attribute :unit_price, :decimal, allow_nil?: false
    attribute :tax_rate, :decimal, allow_nil?: false
    attribute :amount, :decimal, allow_nil?: false

    attribute :payment_intent_id, :string
    attribute :confirmed_at, :utc_datetime
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

    calculate :holds_seats?,
              :boolean,
              expr(status == :confirmed or (status == :pending and inserted_at > ago(@hold_minutes, :minute)))
  end
end
