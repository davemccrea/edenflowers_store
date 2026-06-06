defmodule Edenflowers.Store.Driver do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  @locales Edenflowers.Locales.all()

  postgres do
    table "drivers"
    repo Edenflowers.Repo
  end

  code_interface do
    define :list, action: :read
    define :list_active, action: :active
    define :get_by_id, action: :by_id, args: [:id]
    define :create, action: :create
    define :deactivate, action: :deactivate
    define :reactivate, action: :reactivate
  end

  actions do
    # Drivers are never destroyed; deactivation preserves history and prevents
    # new assignments while keeping existing links usable.
    defaults [
      :read,
      create: [:name, :email, :preferred_locale, :active],
      update: [:name, :email, :preferred_locale]
    ]

    read :active do
      filter expr(active == true)
      prepare build(sort: [name: :asc])
    end

    read :by_id do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true
    end

    update :deactivate do
      change set_attribute(:active, false)
    end

    update :reactivate do
      change set_attribute(:active, true)
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    bypass actor_attribute_equals(:system, true) do
      authorize_if action_type(:read)
    end

    policy always() do
      forbid_if always()
    end
  end

  validations do
    validate one_of(:preferred_locale, @locales)
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false, public?: true
    attribute :email, :ci_string, allow_nil?: false, public?: true

    attribute :preferred_locale, :string do
      allow_nil? false
      public? true
      default Edenflowers.Locales.default()
    end

    attribute :active, :boolean, allow_nil?: false, default: true, public?: true

    timestamps()
  end

  relationships do
    has_many :delivery_routes, Edenflowers.Store.DeliveryRoute
  end

  identities do
    identity :unique_email, [:email]
  end
end
