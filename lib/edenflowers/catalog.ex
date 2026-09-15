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
      define :list_products_by_category_slug, action: :get_by_category_slug, args: [:slug]
      define :get_product_by_id, action: :by_id, args: [:id]
    end

    resource Edenflowers.Catalog.ProductVariant do
      define :get_variant_by_id, action: :by_id, args: [:id]
      define :list_card_drawer_variants, action: :for_card_drawer
    end

    resource Edenflowers.Catalog.ProductCategory do
      define :list_categories, action: :get_all
      define :get_category_by_slug, action: :get_by_slug, args: [:slug]
    end
  end
end
