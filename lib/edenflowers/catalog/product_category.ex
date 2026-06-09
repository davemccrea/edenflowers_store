defmodule Edenflowers.Catalog.ProductCategory do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTranslation.Resource]

  postgres do
    table "product_categories"
    repo Edenflowers.Repo
  end

  translations do
    locales Edenflowers.Locales.translatable_atoms()
    fields [:name, :description]
  end

  code_interface do
    define :get_all, action: :get_all
    define :get_by_slug, action: :get_by_slug, args: [:slug]
  end

  actions do
    defaults [:read, :destroy]

    read :get_all do
      filter expr(visibility == :public)
    end

    read :get_by_slug do
      argument :slug, :string, allow_nil?: false
      filter expr(slug == ^arg(:slug) and visibility == :public)
      get? true
    end

    create :create do
      accept [:slug, :visibility, :name, :description, :translations]
    end

    update :update do
      accept [:slug, :visibility, :name, :description, :translations]
    end
  end

  policies do
    # Admin bypass - admins can do anything
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Public read access
    policy action_type(:read) do
      authorize_if always()
    end

    # Only admin via bypass — all others forbidden
    policy action_type([:create, :update, :destroy]) do
      description "All mutations require admin actor (covered by bypass above)."
      forbid_if always()
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :description, :string, allow_nil?: true
    attribute :slug, :string, allow_nil?: false

    # :public — browsable in the store ribbon and at /store/:slug
    # :draft  — work-in-progress, not yet ready to publish
    # :hidden — intentionally kept out of the storefront, products are still
    #           reachable through other surfaces (e.g. card-drawer at checkout)
    attribute :visibility, :atom,
      allow_nil?: false,
      default: :draft,
      constraints: [one_of: [:public, :draft, :hidden]]
  end

  relationships do
    has_many :products, Edenflowers.Catalog.Product
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
