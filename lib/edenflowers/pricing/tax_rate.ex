defmodule Edenflowers.Pricing.TaxRate do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Pricing,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer],
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
    attribute :percentage, :decimal, allow_nil?: false, constraints: [min: 0, max: 1]
  end

  relationships do
    has_many :products, Edenflowers.Catalog.Product
  end

  identities do
    identity :unique_name, [:name]
  end
end
