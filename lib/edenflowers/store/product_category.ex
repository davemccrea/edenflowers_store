defmodule Edenflowers.Store.ProductCategory do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTranslation.Resource]

  postgres do
    table "product_categories"
    repo Edenflowers.Repo
  end

  translations do
    locales Edenflowers.Cldr.AshTranslation.locale_names()
    fields [:name, :description]
  end

  code_interface do
    define :get_all, action: :get_all
    define :get_by_slug, action: :get_by_slug, args: [:slug]
  end

  actions do
    defaults [:read, :destroy]

    read :get_all do
      filter expr(draft == false)
    end

    read :get_by_slug do
      argument :slug, :string, allow_nil?: false
      filter expr(slug == ^arg(:slug) and draft == false)
      get? true
    end

    create :create do
      accept [:slug, :draft, :name, :description, :translations]
    end

    update :update do
      accept [:slug, :draft, :name, :description, :translations]
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
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :description, :string, allow_nil?: true
    attribute :slug, :string, allow_nil?: false
    attribute :draft, :boolean, allow_nil?: false, default: true
  end

  relationships do
    has_many :products, Edenflowers.Store.Product
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
