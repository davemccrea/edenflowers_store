defmodule Edenflowers.Fulfillment.ProductFulfillmentOption do
  use Ash.Resource,
    domain: Edenflowers.Fulfillment,
    data_layer: AshPostgres.DataLayer,
    authorizers: [Ash.Policy.Authorizer]

  postgres do
    table "product_fulfillment_options"
    repo Edenflowers.Repo

    # The composite primary key already indexes product_id first.
    custom_indexes do
      index [:fulfillment_option_id]
    end
  end

  resource do
    description "Join table between Product and FulfillmentOption"
  end

  actions do
    defaults [:read, :destroy, create: [:product_id, :fulfillment_option_id]]
  end

  policies do
    bypass actor_attribute_equals(:admin, true) do
      authorize_if always()
    end

    policy action_type(:read) do
      authorize_if always()
    end
  end

  relationships do
    belongs_to :product, Edenflowers.Catalog.Product do
      primary_key? true
      allow_nil? false
    end

    belongs_to :fulfillment_option, Edenflowers.Fulfillment.FulfillmentOption do
      primary_key? true
      allow_nil? false
    end
  end
end
