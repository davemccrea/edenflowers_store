defmodule Edenflowers.Catalog.Product do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
    extensions: [AshTranslation.Resource]

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

    read :for_store do
      prepare Edenflowers.Catalog.Preparations.VisibleInStore
    end

    read :featured do
      filter expr(featured == true)
      prepare Edenflowers.Catalog.Preparations.VisibleInStore
      prepare build(sort: [position: :asc_nils_last, name: :asc])
    end

    read :by_category do
      argument :category_id, :uuid, allow_nil?: false

      filter expr(product_category_id == ^arg(:category_id))
      prepare Edenflowers.Catalog.Preparations.VisibleInStore
      prepare build(sort: [position: :asc_nils_last, name: :asc])
    end

    create :create do
      accept [
        :name,
        :image_slug,
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
        :image_slug,
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

  # A subscribable product is always delivered free inside the free zone,
  # bought once or not; unticking it would silently start charging every
  # occurrence.
  validations do
    validate attribute_equals(:free_delivery, true),
      where: [attribute_equals(:subscribable, true)],
      message: "must be on for a subscription product"
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :image_slug, :string, allow_nil?: false
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

  aggregates do
    min :cheapest_price, :product_variants, :price
  end

  identities do
    identity :unique_name, [:name]
  end
end
