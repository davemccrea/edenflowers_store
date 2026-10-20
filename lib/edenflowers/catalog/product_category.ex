defmodule Edenflowers.Catalog.ProductCategory.Visibility do
  use Ash.Type.Enum, values: [:public, :draft, :hidden]
end

defmodule Edenflowers.Catalog.ProductCategory do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTranslation.Resource]

  require Ash.Query

  postgres do
    table "product_categories"
    repo Edenflowers.Repo
  end

  translations do
    locales Edenflowers.Locales.translatable_atoms()
    fields [:name, :description, :slug]
  end

  actions do
    defaults [:read, :destroy, :create, :update]
    default_accept [:slug, :visibility, :add_on, :name, :description, :translations]

    read :public do
      filter expr(visibility == :public)
    end

    # A store URL carries the slug in its own language, falling back to the
    # English `slug` where the category has no translation.
    read :public_by_slug do
      get? true
      argument :slug, :string, allow_nil?: false
      argument :locale, :atom, allow_nil?: false
      filter expr(visibility == :public)

      prepare fn query, _context ->
        url_slug = Ash.Query.get_argument(query, :slug)
        locale = Ash.Query.get_argument(query, :locale)

        if locale in Edenflowers.Locales.translatable_atoms() do
          Ash.Query.filter(
            query,
            get_path(translations, ^[locale, :slug]) == ^url_slug or
              (is_nil(get_path(translations, ^[locale, :slug])) and slug == ^url_slug)
          )
        else
          Ash.Query.filter(query, slug == ^url_slug)
        end
      end
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
