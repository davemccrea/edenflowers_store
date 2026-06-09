defmodule Edenflowers.Catalog do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Catalog.Product
    resource Edenflowers.Catalog.ProductVariant
    resource Edenflowers.Catalog.ProductCategory
  end
end
