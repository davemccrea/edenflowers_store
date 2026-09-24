defmodule Edenflowers.Courses.Course do
  use Ash.Resource,
    domain: Edenflowers.Courses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTranslation.Resource]

  postgres do
    repo Edenflowers.Repo
    table "courses"
  end

  translations do
    locales Edenflowers.Locales.translatable_atoms()
    fields [:name, :description]
  end

  actions do
    defaults [:read, :destroy]

    @accept [
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
      :tax_rate_id,
      :translations
    ]

    create :create do
      accept @accept
    end

    update :update do
      accept @accept
    end

    read :upcoming do
      filter expr(date >= today())
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
    attribute :price, :decimal, allow_nil?: false

    timestamps()
  end

  relationships do
    has_many :course_registrations, Edenflowers.Courses.CourseRegistration
    belongs_to :tax_rate, Edenflowers.Pricing.TaxRate, allow_nil?: false
  end

  calculations do
    calculate :seats_left, :integer, expr(total_places - seats_taken)
    # Helsinki's date, not the database's UTC `today()`, so the page and the
    # cutoff in ReserveSeats agree around midnight.
    calculate :booking_open?,
              :boolean,
              expr(
                register_before >= fragment("(now() AT TIME ZONE 'Europe/Helsinki')::date") and
                  seats_left > 0
              )
  end

  aggregates do
    # Unauthorized on purpose: a visitor may not read other people's bookings,
    # but everyone needs the count to see how many seats are left.
    sum :seats_taken, :course_registrations, :seats do
      filter expr(holds_seats?)
      default 0
      authorize? false
    end
  end
end
