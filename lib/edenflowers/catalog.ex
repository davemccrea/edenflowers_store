defmodule Edenflowers.Catalog do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  resources do
    resource Edenflowers.Catalog.Product do
      define :list_store_products, action: :for_store
      define :list_featured_products, action: :featured
      define :list_products_by_category, action: :by_category, args: [:category_id]
      define :get_product_by_id, action: :read, get_by: [:id]
    end

    resource Edenflowers.Catalog.ProductVariant do
      define :list_card_drawer_variants, action: :for_card_drawer
      define :list_sold_out_variants, action: :sold_out
      define :get_variant_by_id, action: :read, get_by: [:id]
    end

    resource Edenflowers.Catalog.ProductCategory do
      define :list_categories, action: :public
      define :get_category_by_slug, action: :public, get_by: [:slug]
    end
  end
end
