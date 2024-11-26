defmodule Edenflowers.Store.ProductCategory do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "product_categories"
    repo Edenflowers.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
  end

  relationships do
    has_many :products, Edenflowers.Store.Product
  end
end
