defmodule Edenflowers.Catalog.Product do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTranslation.Resource]

  alias Edenflowers.Catalog.Changes
  alias Edenflowers.Catalog.Preparations
  alias Edenflowers.Catalog.Validations

  postgres do
    table "products"
    repo Edenflowers.Repo
  end

  translations do
    locales Edenflowers.Locales.translatable_atoms()
    fields [:name, :description]
  end

  actions do
    defaults [:read, :destroy]

    read :for_product_page do
      prepare build(load: [:main_photo_slug, :product_category, :tax_rate, product_variants: [:photo_slug]])
    end

    read :for_store do
      prepare Preparations.VisibleInStore
    end

    read :featured do
      filter expr(featured == true)
      prepare Preparations.VisibleInStore
      prepare build(sort: [position: :asc_nils_last, name: :asc])
    end

    # Categories are data, so the bouquet category is found by its English slug.
    read :bouquets do
      filter expr(product_category.slug == "bouquets")
      prepare Preparations.VisibleInStore
    end

    read :subscribable do
      filter expr(subscribable == true)
      prepare Preparations.VisibleInStore
      prepare build(sort: [position: :asc_nils_last, name: :asc])
    end

    read :by_category do
      argument :category_id, :uuid, allow_nil?: false

      filter expr(product_category_id == ^arg(:category_id))
      prepare Preparations.VisibleInStore
      prepare build(sort: [position: :asc_nils_last, name: :asc])
    end

    create :create do
      accept [
        :name,
        :photo_slugs,
        :hidden_photo_slugs,
        :description,
        :tax_rate_id,
        :product_category_id,
        :draft,
        :featured,
        :position,
        :free_delivery,
        :subscribable,
        :translations
      ]

      argument :product_variants, {:array, :map}

      validate Validations.SizePhotosAreProducts

      change Changes.TidyHiddenPhotos

      change manage_relationship(:product_variants,
               type: :direct_control,
               on_no_match: {:create, :create},
               on_match: {:update, :update},
               on_missing: :ignore
             )
    end

    update :update do
      accept [
        :name,
        :photo_slugs,
        :hidden_photo_slugs,
        :description,
        :tax_rate_id,
        :product_category_id,
        :draft,
        :featured,
        :position,
        :free_delivery,
        :subscribable,
        :translations
      ]

      argument :product_variants, {:array, :map}
      require_atomic? false

      validate Validations.SizePhotosAreProducts

      validate {Edenflowers.Orders.Validations.NotReferencedByCurrentSubscription,
                reference: :product, field: :subscribable, changing_to: {:subscribable, false}}

      validate {Edenflowers.Orders.Validations.NotReferencedByCurrentSubscription,
                reference: :product, field: :free_delivery, changing_to: {:free_delivery, false}}

      # A size left out of the form was removed; destroying archives it.
      change manage_relationship(:product_variants,
               type: :direct_control,
               on_no_match: {:create, :create},
               on_match: {:update, :update},
               on_missing: {:destroy, :destroy}
             )

      change Changes.TidyHiddenPhotos
      change Changes.ClearRemovedSizePhotos
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
    # In display order; the first is the main photo, see `main_photo_slug`.
    attribute :photo_slugs, {:array, :string}, allow_nil?: false, constraints: [min_length: 1, max_length: 8]
    # Left out of the store's gallery but still pickable by a size. Never the main photo.
    attribute :hidden_photo_slugs, {:array, :string}, allow_nil?: false, default: []
    attribute :description, :string, allow_nil?: false
    attribute :draft, :boolean, allow_nil?: false, default: true
    attribute :featured, :boolean, allow_nil?: false, default: false
    # Store order within a category: 0 first, unset after all positioned products.
    attribute :position, :integer, constraints: [min: 0]
    attribute :free_delivery, :boolean, allow_nil?: false, default: false
    # Can also be bought as a Subscription, which the customer opts into on
    # the product page. Bought once, it is like any other product.
    attribute :subscribable, :boolean, allow_nil?: false, default: false
  end

  relationships do
    belongs_to :tax_rate, Edenflowers.Pricing.TaxRate, allow_nil?: false
    belongs_to :product_category, Edenflowers.Catalog.ProductCategory, allow_nil?: false

    has_many :product_variants, Edenflowers.Catalog.ProductVariant
  end

  calculations do
    calculate :main_photo_slug, :string, expr(at(photo_slugs, 0))

    calculate :sold_out?,
              :boolean,
              expr(
                exists(product_variants) and
                  not exists(product_variants, is_nil(stock_quantity) or stock_quantity > 0)
              )
  end

  aggregates do
    min :cheapest_price, :product_variants, :price
  end

  identities do
    identity :unique_name, [:name]
  end
end
