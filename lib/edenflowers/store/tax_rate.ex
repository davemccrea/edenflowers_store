defmodule Edenflowers.Store.TaxRate do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    extensions: [AshArchival.Resource]

  postgres do
    table "tax_rates"
    repo Edenflowers.Repo
  end

  actions do
    defaults [:read, :destroy]

    create :create do
      accept [:name, :percentage]
    end
  end

  attributes do
    uuid_primary_key :id
    attribute :name, :string, allow_nil?: false
    attribute :percentage, :decimal, allow_nil?: false, constraints: [min: 0, max: 100]
  end

  relationships do
    has_many :products, Edenflowers.Store.Product
  end

  identities do
    identity :unique_name, [:name]
  end
end
