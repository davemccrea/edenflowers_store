defmodule Edenflowers.Store.ProductVariant do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "product_variants"
    repo Edenflowers.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:price, :size, :image, :stock_trackable, :stock_quantity, :product_id]
    end

    update :update do
      accept [:price, :size, :image, :stock_trackable, :stock_quantity]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :price, :decimal, allow_nil?: false
    attribute :size, Edenflowers.Store.ProductVariantSize
    attribute :image, :string, allow_nil?: false
    attribute :stock_trackable, :boolean, default: false
    attribute :stock_quantity, :integer, constraints: [min: 0]
  end

  relationships do
    belongs_to :product, Edenflowers.Store.Product, allow_nil?: false
  end
end
