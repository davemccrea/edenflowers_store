defmodule Edenflowers.Services.CourseRegistration do
  use Ash.Resource,
    domain: Edenflowers.Services,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    repo Edenflowers.Repo
    table "course_registrations"
  end

  code_interface do
    define :list_registrations, action: :read
    define :register_for_course, action: :create
    define :get_registration, action: :read, get_by: [:id]
  end

  policies do
    # Admin bypass - admins can do anything
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Anyone can create registrations (for guest registration flow)
    policy action_type(:create) do
      authorize_if always()
    end

    # Users can read and update their own registrations
    # For registrations without a user (guest registrations), only admins can access
    policy action_type([:read, :update]) do
      authorize_if expr(user_id == ^actor(:id))
    end
  end

  actions do
    defaults [:read, :destroy, update: :*]

    create :create do
      accept [:name, :email, :course_id, :status]
      # Automatically set user_id from actor if authenticated
      change fn changeset, _context ->
        case changeset.context[:actor] do
          %{id: user_id} -> Ash.Changeset.force_change_attribute(changeset, :user_id, user_id)
          _ -> changeset
        end
      end
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
    belongs_to :user, Edenflowers.Accounts.User do
      allow_nil? true
    end

    belongs_to :course, Edenflowers.Services.Course
  end
end
