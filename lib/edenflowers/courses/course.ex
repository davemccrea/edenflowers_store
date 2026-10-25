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
      description "Courses from today on, in Helsinki time, soonest first, for the courses page and sitemap."
      # Helsinki's date, like booking_open?, so a course stays listed until its day ends in Finland.
      filter expr(date >= helsinki_today())
      prepare build(default_sort: [date: :asc, start_time: :asc])
    end

    read :admin_list do
      description "Courses for the admin list, paginated, soonest first, with seats booked and whether any " <>
                    "booking is still to settle."

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

  relationships do
    has_many :course_registrations, Edenflowers.Courses.CourseRegistration do
      description "Every registration in any status: checkouts in progress, Invites, Course bookings and " <>
                    "cancelled ones."
    end

    has_many :bookings, Edenflowers.Courses.CourseRegistration do
      description "Course bookings, oldest first. Cancelled ones stay so Jennie can see who dropped out."
      filter expr(status in [:confirmed, :cancelled])
      sort inserted_at: :asc
    end

    has_many :invites, Edenflowers.Courses.CourseRegistration do
      description "Invites Jennie sent that haven't been paid yet, oldest first. A checkout still in progress " <>
                    "has no Payment Link, so it isn't one."

      filter expr(status == :pending and not is_nil(payment_link_token))
      sort inserted_at: :asc
    end

    belongs_to :tax_rate, Edenflowers.Pricing.TaxRate do
      description "The VAT rate included in the course price."
      allow_nil? false
    end
  end

  calculations do
    calculate :ended?,
              :boolean,
              expr(fragment("(? + ?) AT TIME ZONE 'Europe/Helsinki'", date, end_time) <= ^arg(:now)) do
      description "Whether the course's end time, in Helsinki time, has passed by `now` (default: the present)."
      argument :now, :utc_datetime_usec, allow_nil?: false, default: &DateTime.utc_now/0
    end

    calculate :seats_left, :integer, expr(total_places - seats_booked) do
      description "Places not yet taken by a confirmed Course booking. Unpaid checkouts and Invites hold none."
    end

    # Helsinki's date, not the database's UTC `today()`, so the page and the
    # cutoff in PriceBooking agree around midnight.
    calculate :booking_open?,
              :boolean,
              expr(
                register_before >= helsinki_today() and
                  seats_left > 0
              ) do
      description "Whether customers can book online: on or before register_before, counted in Helsinki days, " <>
                    "with places left."
    end

    calculate :to_settle?, :boolean, expr(exists(bookings, committed? and not settled?)) do
      description "Whether any confirmed or cancelled booking still has a Balance to collect or refund."
    end

    calculate :period,
              :atom,
              expr(if date >= helsinki_today() or to_settle?, do: :current, else: :past) do
      description "Which admin list tab it shows under. A past course stays :current until every booking on it " <>
                    "is settled."

      constraints one_of: [:current, :past]
    end
  end

  aggregates do
    # Unauthorized on purpose: a visitor may not read other people's bookings,
    # but everyone needs the count to see how many seats are left.
    sum :seats_booked, :course_registrations, :seats_held do
      description "Places taken by confirmed Course bookings, less seats Jennie removed. Only paid places count."
      filter expr(status == :confirmed)
      default 0
      authorize? false
    end
  end
end
