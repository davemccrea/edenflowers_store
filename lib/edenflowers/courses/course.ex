defmodule Edenflowers.Courses.Course do
  @moduledoc """
  A scheduled florist course with translated details, capacity, price, and booking deadline.
  """

  use Ash.Resource,
    domain: Edenflowers.Courses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTranslation.Resource]

  use GettextSigils, backend: EdenflowersWeb.Gettext

  postgres do
    repo Edenflowers.Repo
    table "courses"
    migration_types price: :decimal

    check_constraints do
      check_constraint :price, "courses_valid_price",
        check: "price >= 0 AND price = round(price, 2)",
        message: "must be a non-negative amount in whole cents"
    end
  end

  translations do
    locales Edenflowers.Locales.translatable_atoms()
    fields [:name, :description]
  end

  actions do
    defaults [:read, :destroy, :create, :update]

    default_accept [
      :name,
      :description,
      :location_name,
      :location_address,
      :image_slug,
      :date,
      :start_time,
      :end_time,
      :register_before,
      :total_places,
      :price,
      :cancellation_days,
      :cancellation_fee_percent,
      :tax_rate_id,
      :language,
      :translations
    ]

    read :upcoming do
      # Helsinki's date, like booking_open?, so a course stays listed until its day ends in Finland.
      filter expr(date >= helsinki_today())
      prepare build(default_sort: [date: :asc, start_time: :asc])
    end

    read :admin_list do
      pagination offset?: true, countable: true, required?: false
      prepare build(default_sort: [date: :asc, start_time: :asc], load: [:seats_booked, :to_settle?])
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      description "All mutations require admin actor (covered by bypass above)."
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :description, :string, allow_nil?: false
    attribute :location_name, :string, allow_nil?: false
    attribute :location_address, :string, allow_nil?: false
    attribute :image_slug, :string, allow_nil?: false
    attribute :date, :date, allow_nil?: false
    attribute :start_time, :time, allow_nil?: false
    attribute :end_time, :time, allow_nil?: false
    attribute :register_before, :date, allow_nil?: false
    attribute :total_places, :integer, allow_nil?: false
    attribute :price, :decimal, allow_nil?: false, constraints: [min: 0, scale: 2]

    # A booking cancelled at least this many days before the course is refunded in full.
    attribute :cancellation_days, :integer, allow_nil?: false, default: 7, constraints: [min: 0]
    # What's kept of the price after that; 100 means no refund.
    attribute :cancellation_fee_percent, :integer, allow_nil?: false, default: 0, constraints: [min: 0, max: 100]

    # The language the course is taught in, not the language of its page.
    attribute :language, :atom, allow_nil?: false, default: :sv, constraints: [one_of: [:sv, :fi, :en]]

    timestamps()
  end

  @doc """
  The course's cancellation terms, as the course page, the FAQ and the
  booking emails all state them, in the current Gettext locale.
  """
  def cancellation_terms(course) do
    full_refund = ~t"Cancel at least #{days = course.cancellation_days} days before the course for a full refund."

    case course.cancellation_fee_percent do
      0 -> full_refund
      100 -> full_refund <> " " <> ~t"After that, the booking can't be refunded."
      fee -> full_refund <> " " <> ~t"After that, #{fee = fee}% of the price is kept."
    end
  end

  @doc """
  What to refund a booking that cost `price` and still holds `held` when it's
  cancelled `today`: everything before the cancellation deadline, and after
  it all but the course's fee. Jennie can still change it.
  """
  def refund_on_cancelling(course, price, held, today) do
    if Date.diff(course.date, today) >= course.cancellation_days do
      held
    else
      kept = price |> Decimal.mult(course.cancellation_fee_percent) |> Decimal.div(100) |> Decimal.round(2)
      held |> Decimal.sub(kept) |> Decimal.max(0)
    end
  end

  relationships do
    has_many :course_registrations, Edenflowers.Courses.CourseRegistration

    # No pending bookings: an unpaid hold is either still at checkout or
    # abandoned, and neither is someone who is coming. Cancelled ones stay so
    # Jennie can see who dropped out.
    has_many :bookings, Edenflowers.Courses.CourseRegistration do
      filter expr(status in [:awaiting_payment, :confirmed, :cancelled])
      sort inserted_at: :asc
    end

    belongs_to :tax_rate, Edenflowers.Pricing.TaxRate, allow_nil?: false
  end

  calculations do
    calculate :seats_left, :integer, expr(total_places - seats_taken)
    # Helsinki's date, not the database's UTC `today()`, so the page and the
    # cutoff in ReserveSeats agree around midnight.
    calculate :booking_open?,
              :boolean,
              expr(
                register_before >= helsinki_today() and
                  seats_left > 0
              )

    calculate :to_settle?, :boolean, expr(exists(bookings, committed? and not settled?))

    # A past course stays current until every booking on it is settled.
    calculate :period,
              :atom,
              expr(if date >= helsinki_today() or to_settle?, do: :current, else: :past),
              constraints: [one_of: [:current, :past]]
  end

  aggregates do
    # Unauthorized on purpose: a visitor may not read other people's bookings,
    # but everyone needs the count to see how many seats are left.
    sum :seats_taken, :course_registrations, :seats_held do
      filter expr(holds_seats?)
      default 0
      authorize? false
    end

    # Leaves out holds still at checkout, so the admin counts only who is
    # coming or whose place waits on their payment link.
    sum :seats_booked, :course_registrations, :seats_held do
      filter expr(status in [:awaiting_payment, :confirmed])
      default 0
    end
  end
end
