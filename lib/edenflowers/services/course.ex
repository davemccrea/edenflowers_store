defmodule Edenflowers.Services.Course do
  use Ash.Resource,
    domain: Edenflowers.Services,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo Edenflowers.Repo
    table "courses"
  end

  code_interface do
    define :list_courses, action: :read
    define :get_course, action: :read, get_by: [:id]
    define :create_course, action: :create
    define :list_upcoming_courses, action: :upcoming
    define :list_past_courses, action: :past
  end

  policies do
    # Admin bypass - admins can do anything
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Public read access to courses
    policy action_type(:read) do
      authorize_if always()
    end
  end

  actions do
    defaults [:read, :update, :destroy]

    create :create do
      accept [
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
        :price
      ]
    end

    read :upcoming do
      filter expr(date >= today())
    end

    read :past do
      filter expr(date < today())
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
    has_many :course_registrations, Edenflowers.Services.CourseRegistration
  end

  aggregates do
    count :total_registrations, :course_registrations do
      filter expr(status == :confirmed)
    end
  end
end
