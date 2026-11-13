defmodule Edenflowers.Courses.Course do
  @moduledoc """
  A scheduled florist course with translated details, capacity, price, and booking deadline.
  """

  use Ash.Resource,
    domain: Edenflowers.Courses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    notifiers: [Ash.Notifier.PubSub],
    extensions: [AshTranslation.Resource]

  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Events

  @slug_options [former_slugs: Edenflowers.Courses.FormerCourseSlug, owner_key: :course_id, fallback: "course"]

  attributes do
    uuid_primary_key :id

    attribute :name, :string do
      description "The course's name in English. The Swedish and Finnish ones are in translations, as are the description's."
      allow_nil? false
    end

    attribute :draft, :boolean do
      description "Hidden from the public courses list and sitemap while Jennie prepares it."
      allow_nil? false
      default true
    end

    attribute :slug, :string do
      description "Where the course's page lives, as in /courses/spring-wreath-workshop. Made from the English " <>
                    "name when the course is created and kept when it is renamed; Jennie can edit it in the " <>
                    "course form."

      allow_nil? false
      public? true
    end

    attribute :description, :string, allow_nil?: false
    attribute :location_name, :string, allow_nil?: false
    attribute :location_address, :string, allow_nil?: false
    attribute :image_slug, :string, allow_nil?: false

    attribute :photo_credit_name, :string do
      description "Optional photographer credit shown with the course photo."
    end

    attribute :photo_credit_url, :string do
      description "Optional photographer website linked from the photo credit."
    end

    attribute :date, :date do
      description "The day it is held. start_time and end_time are Helsinki times on that day."
      allow_nil? false
    end

    attribute :start_time, :time, allow_nil?: false
    attribute :end_time, :time, allow_nil?: false

    attribute :register_before, :date do
      description "The last day customers can book online, that day included, in Helsinki. Jennie can still " <>
                    "add a booking herself after it."

      allow_nil? false
    end

    attribute :total_places, :integer do
      description "How many places the course has. seats_left is what confirmed bookings leave of it."
      allow_nil? false
    end

    attribute :price, :decimal do
      description "What one place costs in euros, VAT included. A booking's amount is this times its seats, " <>
                    "snapshotted when it is made."

      allow_nil? false
      constraints min: 0, scale: 2
    end

    attribute :cancellation_days, :integer do
      description "A booking cancelled at least this many days before the course is refunded in full."
      allow_nil? false
      default 7
      constraints min: 0
    end

    attribute :cancellation_fee_percent, :integer do
      description "What is kept of the price when a booking is cancelled later than cancellation_days allows; " <>
                    "100 means no refund."

      allow_nil? false
      default 0
      constraints min: 0, max: 100
    end

    attribute :language, :atom do
      description "The language the course is taught in, not the language of its page."
      allow_nil? false
      default :sv
      constraints one_of: [:sv, :fi, :en]
    end

    timestamps()
  end

  relationships do
    has_many :former_slugs, Edenflowers.Courses.FormerCourseSlug do
      description "Slugs the course used to have. Links with them redirect to its current slug."
    end

    has_many :course_registrations, Edenflowers.Courses.CourseRegistration do
      description "Every retained registration in any status: unfinished checkouts, accepted bookings and " <>
                    "cancelled ones."
    end

    has_many :bookings, Edenflowers.Courses.CourseRegistration do
      description "Course bookings, oldest first. Cancelled ones stay so Jennie can see who dropped out."
      filter expr(status in [:confirmed, :cancelled])
      sort inserted_at: :asc
    end

    belongs_to :tax_rate, Edenflowers.Pricing.TaxRate do
      description "The VAT rate included in the course price."
      allow_nil? false
    end
  end

  calculations do
    calculate :match_rank,
              :integer,
              expr(
                fragment(
                  "least(?, ?, ?)",
                  match_rank(name, ^arg(:term)),
                  match_rank(translations[:"sv-FI"][:name], ^arg(:term)),
                  match_rank(translations[:fi][:name], ^arg(:term))
                )
              ) do
      description "How closely the admin search term matches what a result row shows (see `match_rank`): " <>
                    "0 exact, 1 at the start of a word, 2 elsewhere, 3 for a match in a field the row " <>
                    "doesn't show. The search sorts by it."

      argument :term, :ci_string, allow_nil?: false
    end

    calculate :ended?,
              :boolean,
              expr(fragment("(? + ?) AT TIME ZONE 'Europe/Helsinki'", date, end_time) <= ^arg(:now)) do
      description "Whether the course's end time, in Helsinki time, has passed by `now` (default: the present)."
      argument :now, :utc_datetime_usec, allow_nil?: false, default: &DateTime.utc_now/0
    end

    calculate :seats_left, :integer, expr(total_places - seats_booked) do
      description "Places not yet committed to confirmed bookings, paid or unpaid. Pending checkouts hold none."
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
      description "Places committed to confirmed bookings, paid or unpaid, less seats Jennie removed."
      filter expr(status == :confirmed)
      default 0
      authorize? false
    end
  end

  identities do
    identity :unique_slug, [:slug]
  end

  actions do
    defaults [:read, :destroy]

    default_accept [
      :name,
      :description,
      :location_name,
      :location_address,
      :image_slug,
      :photo_credit_name,
      :photo_credit_url,
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
      :translations,
      :slug,
      :draft
    ]

    create :create do
      description "Creates a course from the admin form."
      primary? true
      # SetSlug makes one from the name when the form leaves it blank.
      allow_nil_input [:slug]
      change {Edenflowers.Slug.SetSlug, @slug_options}
    end

    update :update do
      description "Saves the admin course form."
      primary? true
      require_atomic? false
      change {Edenflowers.Slug.SetSlug, @slug_options}
    end

    action :current_slug, :string do
      description "Where an outdated course link should go: the current slug of the course whose id or " <>
                    "former slug `param` is, or nil when `param` is neither, such as a current slug. Course " <>
                    "pages redirect old links with it."

      allow_nil? true

      argument :param, :string do
        description "The last part of a course URL."
        allow_nil? false
      end

      run {Edenflowers.Slug.CurrentSlug, @slug_options}
    end

    read :upcoming do
      description "Published courses from today on, in Helsinki time, soonest first, for the courses page and sitemap."
      # Helsinki's date, like booking_open?, so a course stays listed until its day ends in Finland.
      filter expr(draft == false and date >= helsinki_today())
      prepare build(default_sort: [date: :asc, start_time: :asc])
    end

    read :search do
      description "Admin search for courses, drafts and past ones included, by name in any language, latest first."

      argument :term, :ci_string, allow_nil?: false

      filter expr(
               contains(name, ^arg(:term)) or contains(translations[:"sv-FI"][:name], ^arg(:term)) or
                 contains(translations[:fi][:name], ^arg(:term))
             )

      prepare Edenflowers.Preparations.RankByMatch
      prepare build(sort: [date: :desc], load: [:seats_booked, :ended?])
    end

    read :admin_show do
      description "A course with its bookings and everything the admin course page and its drawers show, " <>
                    "including what Jennie may still do with each booking."

      prepare build(
                load: [
                  :seats_booked,
                  :ended?,
                  bookings: [
                    :cancelled?,
                    :amount_paid,
                    :amount_held,
                    :holds_money?,
                    :balance,
                    :to_collect?,
                    :to_refund?,
                    :cancelled_unsettled?,
                    :refund_methods,
                    :default_refund_method,
                    :refundable?,
                    :seats_held,
                    :seat_removable?,
                    :stripe_payment_intent_id,
                    :payment_link_open?,
                    :payment_reminder?,
                    :refunds,
                    :receipt_available?,
                    :paper_trail_versions,
                    payments: [:undoable?]
                  ]
                ]
              )
    end

    read :admin_list do
      description "Courses for the admin list, paginated, soonest first, with seats booked and whether any " <>
                    "booking is still to settle."

      pagination offset?: true, countable: true, required?: false
      prepare build(default_sort: [date: :asc, start_time: :asc], load: [:seats_booked, :ended?, :to_settle?])
    end
  end

  validations do
    validate match(:photo_credit_url, ~r{\Ahttps?://[^\s/?#]+(?:[/?#][^\s]*)?\z}i),
      where: present(:photo_credit_url),
      message: "Must be a website address starting with http:// or https://"

    validate present(:photo_credit_name), where: present(:photo_credit_url)
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
  The same terms for a booking with nothing paid yet, which the booking
  emails state: a late cancel charges the cancellation fee
  (`CourseRegistration.default_cancellation_charge`), as nothing is there to
  refund or keep.
  """
  def unpaid_cancellation_terms(course) do
    free = ~t"Cancel at least #{days = course.cancellation_days} days before the course at no cost."

    case course.cancellation_fee_percent do
      0 -> free
      100 -> free <> " " <> ~t"After that, the full price is charged."
      fee -> free <> " " <> ~t"After that, #{fee = fee}% of the price is charged."
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end

    policy action(:current_slug) do
      authorize_if always()
    end

    policy action_type([:create, :update, :destroy]) do
      description "All mutations require admin actor (covered by bypass above)."
      forbid_if always()
    end
  end

  # The admin's course list follows course changes; bookings publish through
  # CourseRegistration to its own topics.
  pub_sub do
    module EdenflowersWeb.Endpoint

    publish_all :create, Events.admin_courses()
    publish_all :update, Events.admin_courses()
    publish_all :destroy, Events.admin_courses()

    publish_all :create, Events.admin_course(:id)
    publish_all :update, Events.admin_course(:id)
    publish_all :destroy, Events.admin_course(:id)
  end

  translations do
    locales Edenflowers.Locales.translatable_atoms()
    fields [:name, :description]
  end

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
end

defimpl Phoenix.Param, for: Edenflowers.Courses.Course do
  def to_param(course), do: course.slug
end
