defmodule Edenflowers.Store do
  use Ash.Domain

  resources do
    resource Edenflowers.Store.Product
    resource Edenflowers.Store.ProductVariant
    resource Edenflowers.Store.ProductCategory
    resource Edenflowers.Store.FulfillmentOption
    resource Edenflowers.Store.ProductFulfillmentOption
    resource Edenflowers.Store.TaxRate
    resource Edenflowers.Store.Promotion
    resource Edenflowers.Store.OpeningHours
    resource Edenflowers.Store.Order
    resource Edenflowers.Store.LineItem
  end
end
