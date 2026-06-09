defmodule Edenflowers.Fulfillment.ProductFulfillmentOption do
  use Ash.Resource,
    domain: Edenflowers.Fulfillment,
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
    defaults [
      :read,
      :destroy,
      create: [:product_id, :fulfillment_option_id],
      update: [:product_id, :fulfillment_option_id]
    ]
  end

  attributes do
    uuid_primary_key :id
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
