defmodule Edenflowers.Catalog.Product do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Catalog,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "products"
    repo Edenflowers.Repo
  end

  actions do
    defaults [:read, :destroy]

    read :for_store do
      prepare Edenflowers.Catalog.Product.Preparations.VisibleInStore
    end

    read :featured do
      filter expr(featured == true)
      prepare Edenflowers.Catalog.Product.Preparations.VisibleInStore
    end

    read :by_category do
      argument :category_id, :uuid, allow_nil?: false

      filter expr(product_category_id == ^arg(:category_id))
      prepare Edenflowers.Catalog.Product.Preparations.VisibleInStore
    end

    read :get_by_category_slug do
      argument :slug, :string, allow_nil?: false

      filter expr(product_category.slug == ^arg(:slug))
      prepare Edenflowers.Catalog.Product.Preparations.VisibleInStore
      prepare build(load: [:tax_rate])
    end

    read :by_id do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true
      prepare build(load: [:product_category])
    end

    create :create do
      accept [:name, :image_slug, :description, :tax_rate_id, :product_category_id, :draft, :featured]
      argument :fulfillment_option_ids, {:array, :uuid}

      change manage_relationship(:fulfillment_option_ids, :fulfillment_options, type: :append_and_remove)
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
    attribute :image_slug, :string, allow_nil?: false
    attribute :description, :string, allow_nil?: false
    attribute :draft, :boolean, allow_nil?: false, default: true
    attribute :featured, :boolean, allow_nil?: false, default: false
  end

  relationships do
    belongs_to :tax_rate, Edenflowers.Pricing.TaxRate, allow_nil?: false
    belongs_to :product_category, Edenflowers.Catalog.ProductCategory, allow_nil?: false

    has_many :product_variants, Edenflowers.Catalog.ProductVariant

    many_to_many :fulfillment_options, Edenflowers.Fulfillment.FulfillmentOption do
      through Edenflowers.Fulfillment.ProductFulfillmentOption
    end
  end

  aggregates do
    min :cheapest_price, :product_variants, :price
  end

  identities do
    identity :unique_name, [:name]
  end
end
