defmodule Edenflowers.Courses.CourseRegistration do
  use Ash.Resource,
    domain: Edenflowers.Courses,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo Edenflowers.Repo
    table "course_registrations"
  end

  code_interface do
    define :list_registrations, action: :read
    define :register_for_course, action: :register
    define :get_registration, action: :read, get_by: [:id]
  end

  actions do
    defaults [:read, :destroy]

    create :register do
      accept [:name, :email, :course_id]
      change set_attribute(:status, :pending)
      change {Edenflowers.Courses.CourseRegistration.Changes.SetUserFromActor, []}
    end

    update :confirm_payment do
      change atomic_update(:status, :confirmed)
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Anyone can create registrations (for the guest registration flow).
    policy action_type(:create) do
      authorize_if always()
    end

    # Guest registrations have a nil user_id, so this expr only ever matches
    # a logged-in user's own rows — guest rows stay admin-only via the bypass.
    policy action_type([:read, :update]) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :email, :string, allow_nil?: false

    attribute :status, :atom,
      default: :pending,
      constraints: [one_of: [:pending, :confirmed, :cancelled]]

    timestamps()
  end

  relationships do
    belongs_to :user, Edenflowers.Accounts.User do
      allow_nil? true
    end

    belongs_to :course, Edenflowers.Courses.Course
  end
end
