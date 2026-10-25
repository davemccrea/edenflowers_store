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
    default_accept [:slug, :visibility, :add_on, :product_type, :name, :description, :translations]

    read :public do
      description "Categories browsable in the store and listed in the sitemap. Draft and hidden categories are " <>
                    "left out."

      filter expr(visibility == :public)
    end

    read :public_by_slug do
      description "A public category by its URL slug. Draft and hidden categories are not found."
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

    attribute :visibility, __MODULE__.Visibility do
      description ":public is browsable in the store ribbon and at /store/:slug. :draft is work in progress, " <>
                    "not yet ready to publish. :hidden is kept out of the storefront, but its products are still " <>
                    "reachable elsewhere, like the card drawer at checkout."

      allow_nil? false
      default :draft
    end

    attribute :add_on, :boolean do
      description "Its products are Add-ons, like cards and chocolate, that go with flowers: a cart of only " <>
                    "Add-ons can't be checked out, as delivering one alone isn't worth it."

      allow_nil? false
      default false
    end

    attribute :product_type, Edenflowers.Catalog.ProductType, allow_nil?: false, default: :flowers
  end

  relationships do
    has_many :products, Edenflowers.Catalog.Product do
      description "Every product in it, drafts included."
    end
  end

  identities do
    identity :unique_slug, [:slug]
  end
end
