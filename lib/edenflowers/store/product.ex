defmodule Edenflowers.Store.Product do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "products"
    repo Edenflowers.Repo
  end

  code_interface do
    define :get_by_id, action: :get_by_id, args: [:id]
  end

  actions do
    defaults [:read, :destroy]

    read :get_by_id do
      argument :id, :uuid, allow_nil?: false
      filter expr(id == ^arg(:id))
      get? true
    end

    create :create do
      accept [:name, :image_slug, :description, :tax_rate_id, :product_category_id, :draft]
      argument :fulfillment_option_ids, {:array, :uuid}

      change manage_relationship(:fulfillment_option_ids, :fulfillment_options, type: :append_and_remove)
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :image_slug, :string, allow_nil?: false
    attribute :description, :string, allow_nil?: false
    attribute :draft, :boolean, allow_nil?: false, default: true
  end

  relationships do
    belongs_to :tax_rate, Edenflowers.Store.TaxRate, allow_nil?: false
    belongs_to :product_category, Edenflowers.Store.ProductCategory
    has_many :product_variants, Edenflowers.Store.ProductVariant

    many_to_many :fulfillment_options, Edenflowers.Store.FulfillmentOption do
      through Edenflowers.Store.ProductFulfillmentOption
    end
  end

  aggregates do
    min :cheapest_price, :product_variants, :price
  end

  identities do
    identity :unique_name, [:name]
  end
end
