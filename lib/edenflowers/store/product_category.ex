defmodule Edenflowers.Store.ProductCategory do
  use Ash.Resource,
    otp_app: :edenflowers,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "product_categories"
    repo Edenflowers.Repo
  end

  policies do
    # Admin bypass - admins can do anything
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    # Public read access
    policy action_type(:read) do
      authorize_if always()
    end
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
