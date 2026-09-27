defmodule Edenflowers.Catalog do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain, AshAi]

  admin do
    show?(true)
  end

  tools do
    tool :list_store_products, Edenflowers.Catalog.Product, :for_store do
      description "Products visible in the web shop, with category, sizes, prices and stock."
      select [:id, :name, :description, :featured]

      load product_category: [:name],
           product_variants: [:size, :price, :stock_trackable, :stock_quantity]

      load_strict? true
    end
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
    end

    resource Edenflowers.Catalog.ProductCategory do
      define :list_categories, action: :public
      define :get_category_by_slug, action: :public, get_by: [:slug]
    end
  end
end
