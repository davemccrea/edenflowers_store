defmodule Edenflowers.Delivery.Driver do
  use Ash.Resource,
    domain: Edenflowers.Delivery,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  alias Edenflowers.Delivery.Driver.Changes.GenerateToken

  postgres do
    table "drivers"
    repo Edenflowers.Repo
  end

  code_interface do
    define :create, action: :create
    define :update, action: :update
    define :deactivate, action: :deactivate
    define :activate, action: :activate
    define :regenerate_token, action: :regenerate_token
    define :list, action: :read
    define :list_active, action: :list_active
    define :get_by_token, action: :by_token, args: [:token], not_found_error?: false
  end

  actions do
    defaults [:read]

    read :list_active do
      description "Active drivers, the availability pool for assignment selection."
      filter expr(active? == true)
      prepare build(sort: [name: :asc])
    end

    read :by_token do
      description "Resolves a driver from their stable link token for the public /d/:token page."
      get? true
      argument :token, :string, allow_nil?: false
      filter expr(link_token == ^arg(:token))
    end

    create :create do
      accept [:name, :phone, :email, :locale]
      change GenerateToken
    end

    update :update do
      accept [:name, :phone, :email, :locale]
    end

    update :deactivate do
      description "Excludes the driver from new assignment selection; the row and its history remain."
      change set_attribute(:active?, false)
    end

    update :activate do
      change set_attribute(:active?, true)
    end

    update :regenerate_token do
      description "Replaces the link token; the previously copied /d/:token link stops resolving."
      require_atomic? false
      change GenerateToken
    end
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    bypass action(:by_token) do
      authorize_if always()
    end

    policy always() do
      forbid_if always()
    end
  end

  validations do
    validate attribute_in(:locale, Edenflowers.Locales.all())
  end

  attributes do
    uuid_primary_key :id

    attribute :name, :string, allow_nil?: false
    attribute :phone, :string
    attribute :email, :string

    attribute :locale, :string,
      allow_nil?: false,
      default: Edenflowers.Locales.default()

    attribute :active?, :boolean, allow_nil?: false, default: true
    attribute :link_token, :string, allow_nil?: false

    timestamps()
  end

  identities do
    identity :unique_link_token, [:link_token]
  end
end
