defmodule Edenflowers.Catalog.ProductCategory.Visibility do
  @moduledoc """
  Whether a category is public, a draft, or hidden from storefront browsing.
  """

  use Ash.Type.Enum, values: [:public, :draft, :hidden]
end

defmodule Edenflowers.Catalog.ProductCategory do
  @moduledoc """
  Groups products for storefront browsing. Visibility controls whether a category appears publicly, while `add_on` marks products that cannot be checked out alone.
  """

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

  actions do
    defaults [:read, :destroy, :create, :update]
    default_accept [:slug, :visibility, :add_on, :name, :description, :translations]

    read :public do
      filter expr(visibility == :public)
    end

    read :public_by_slug do
      get? true
      argument :slug, :string, allow_nil?: false
      filter expr(visibility == :public and slug == ^arg(:slug))
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
    attribute :description, :string, allow_nil?: true
    attribute :slug, :string, allow_nil?: false

    # :public — browsable in the store ribbon and at /store/:slug
    # :draft  — work-in-progress, not yet ready to publish
    # :hidden — intentionally kept out of the storefront, products are still
    #           reachable through other surfaces (e.g. card-drawer at checkout)
    attribute :visibility, __MODULE__.Visibility, allow_nil?: false, default: :draft

    # Add-ons, like cards and chocolate, go with flowers: a cart of only
    # add-ons can't be checked out, as delivering one alone isn't worth it.
    attribute :add_on, :boolean, allow_nil?: false, default: false
  end

  relationships do
    has_many :products, Edenflowers.Catalog.Product
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
