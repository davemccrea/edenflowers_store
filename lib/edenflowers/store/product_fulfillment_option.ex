defmodule Edenflowers.Store.ProductFulfillmentOption do
  use Ash.Resource,
    domain: Edenflowers.Store,
    data_layer: AshPostgres.DataLayer

  postgres do
    table "product_fulfillment_options"
    repo Edenflowers.Repo

    custom_indexes do
      index [:product_id]
      index [:fulfillment_option_id]
    end
  end

  resource do
    description "Join table between Product and FulfillmentOption"
  end

  actions do
    defaults [:read, :destroy, create: :*, update: :*]
  end

  attributes do
    uuid_primary_key :id
  end

  relationships do
    belongs_to :product, Edenflowers.Store.Product do
      primary_key? true
      allow_nil? false
    end

    belongs_to :fulfillment_option, Edenflowers.Store.FulfillmentOption do
      primary_key? true
      allow_nil? false
    end
  end
end
