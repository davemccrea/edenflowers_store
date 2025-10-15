defmodule Edenflowers.Services.CourseRegistration do
  use Ash.Resource,
    domain: Edenflowers.Services,
    data_layer: AshPostgres.DataLayer

  postgres do
    repo Edenflowers.Repo
    table "course_registrations"
  end

  code_interface do
    define :list_registrations, action: :read
    define :register_for_course, action: :create
    define :get_registration, action: :read, get_by: [:id]
  end

  actions do
    defaults [:read, :destroy, update: :*]

    create :create do
      accept [:name, :email, :course_id, :user_id, :status]
    end

    update :confirm_payment do
      change atomic_update(:status, :confirmed)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :email, :string, allow_nil?: false
    attribute :status, :atom, default: :pending
    timestamps()
  end

  relationships do
    belongs_to :user, Edenflowers.Accounts.User
    belongs_to :course, Edenflowers.Services.Course
  end
end
