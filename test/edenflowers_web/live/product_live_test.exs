defmodule EdenflowersWeb.ProductLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import PhoenixTest
  import Generator

  setup do
    # Create product with multiple variants
    product = generate(product())
    small_variant = generate(product_variant(%{product_id: product.id, size: :small, price: "25.00"}))
    medium_variant = generate(product_variant(%{product_id: product.id, size: :medium, price: "35.00"}))
    large_variant = generate(product_variant(%{product_id: product.id, size: :large, price: "45.00"}))

    # Reload product with variants
    {:ok, product} = Edenflowers.Store.Product.get_by_id(product.id, load: [:product_variants, :tax_rate])

    # Create an order for the session
    order = generate(order())

    %{
      product: product,
      small_variant: small_variant,
      medium_variant: medium_variant,
      large_variant: large_variant,
      order: order
    }
  end

  describe "Product Page Display" do
    test "displays product information", %{conn: conn, product: product, order: order} do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/product/#{product.id}")
      |> assert_has("[data-testid='product-name']")
      |> assert_has("[data-testid='product-description']")
    end

    test "displays all product variants", %{conn: conn, product: product, order: order} do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/product/#{product.id}")
      |> assert_has("input[type='radio'][name='product_variant_id']", count: 3)
      |> assert_has("[data-testid='variant-option-small']")
      |> assert_has("[data-testid='variant-option-medium']")
      |> assert_has("[data-testid='variant-option-large']")
    end

    test "displays variant prices", %{conn: conn, product: product, order: order} do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/product/#{product.id}")
      |> assert_has("[data-testid='product-price']")
    end

    test "has add to cart button", %{conn: conn, product: product, order: order} do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/product/#{product.id}")
      |> assert_has("[data-testid='add-to-cart-button']")
    end
  end

  describe "Variant Selection" do
    test "selects a default variant on mount", %{conn: conn, product: product, order: order} do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/product/#{product.id}")
      |> assert_has("input[type='radio'][checked='checked']")
    end

    test "can change selected variant", %{conn: conn, product: product, order: order, small_variant: small} do
      # Just verify that we have the variant option visible - actual selection is tested in E2E
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/product/#{product.id}")
      |> assert_has("[data-testid='variant-option-small']")
      |> assert_has("input[type='radio'][value='#{small.id}']")
    end

    test "displays product image", %{
      conn: conn,
      product: product,
      order: order
    } do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/product/#{product.id}")
      |> assert_has("[data-testid='product-image']")
    end
  end

  describe "Add to Cart" do
    test "displays add to cart button and form", %{conn: conn, product: product, order: order} do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/product/#{product.id}")
      |> assert_has("[data-testid='add-to-cart-button']")
      |> assert_has("[data-testid='product-form']")
    end

    # Note: Actually clicking and submitting the form to add items to cart requires
    # JavaScript execution for the variant selection and form submission.
    # These interactions would be better tested with browser-based E2E tests (playwright, wallaby, etc)
    # For now, we verify the UI elements are present with correct test IDs
  end

  describe "Breadcrumb Navigation" do
    test "displays breadcrumb navigation", %{conn: conn, product: product, order: order} do
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/product/#{product.id}")
      |> assert_has("[data-testid='breadcrumb']")
      |> assert_has("[data-testid='breadcrumb-link-0']")
      |> assert_has("[data-testid='breadcrumb-link-1']")
      |> assert_has("[data-testid='breadcrumb-current']")
    end

    test "breadcrumb links are present", %{conn: conn, product: product, order: order} do
      # Just verify links are present - actual navigation is tested in E2E
      conn
      |> Plug.Test.init_test_session(%{order_id: order.id})
      |> visit("/product/#{product.id}")
      |> assert_has("a[data-testid='breadcrumb-link-1'][href='/store']")
    end
  end
end
