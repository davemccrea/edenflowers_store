defmodule EdenflowersWeb.Store.ProductLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias Edenflowers.Orders
  alias Edenflowers.Orders.LineItem

  setup %{conn: conn} do
    order = generate(order())
    %{conn: Plug.Test.init_test_session(conn, %{order_id: order.id}), order: order}
  end

  describe "a subscribable product" do
    setup do
      product = generate(product(subscribable: true, free_delivery: true, draft: false))
      %{product: product, variant: generate(product_variant(product_id: product.id))}
    end

    test "is bought once unless the customer subscribes", %{conn: conn, product: product, order: order} do
      {:ok, view, _html} = live(conn, ~p"/product/#{product.id}")

      assert has_element?(view, "[data-testid=product-subscribable]", "Also as a subscription")
      assert has_element?(view, "[data-testid=buy-once-option][checked]")
      refute has_element?(view, "[data-testid=interval-options]")

      view |> form("[data-testid=product-form]") |> render_submit()

      assert [%LineItem{interval_weeks: nil}] = line_items(order)
    end

    test "can be subscribed to every few weeks", %{conn: conn, product: product, variant: variant, order: order} do
      {:ok, view, _html} = live(conn, ~p"/product/#{product.id}")

      view
      |> form("[data-testid=product-form]", %{product_variant_id: variant.id, subscribe: "true"})
      |> render_change()

      assert has_element?(view, "[data-testid=interval-options]")
      assert has_element?(view, "[data-testid=interval-option-4]")

      view
      |> form("[data-testid=product-form]", %{product_variant_id: variant.id, subscribe: "true", interval_weeks: "2"})
      |> render_change()

      view |> form("[data-testid=product-form]") |> render_submit()

      assert [%LineItem{interval_weeks: 2, quantity: 1}] = line_items(order)
    end

    test "says when adding replaces the subscription in the cart", %{
      conn: conn,
      product: product,
      variant: variant,
      order: order
    } do
      Orders.add_line_item!(order.id, variant.id, 1, %{interval_weeks: 2}, authorize?: false)
      {:ok, view, _html} = live(conn, ~p"/product/#{product.id}")

      assert has_element?(view, "[data-testid=replaces-cart-note]", "Replaces the subscription in your cart")
      assert has_element?(view, "[data-testid=add-to-cart-button]", "Update cart")

      view |> form("[data-testid=product-form]") |> render_submit()

      assert [%LineItem{interval_weeks: nil}] = line_items(order)
    end

    test "says when subscribing replaces the bouquet in the cart", %{
      conn: conn,
      product: product,
      variant: variant,
      order: order
    } do
      Orders.add_line_item!(order.id, variant.id, 1, authorize?: false)
      {:ok, view, _html} = live(conn, ~p"/product/#{product.id}")

      assert has_element?(view, "[data-testid=add-to-cart-button]", "Add to cart")
      refute has_element?(view, "[data-testid=replaces-cart-note]")

      view
      |> form("[data-testid=product-form]", %{product_variant_id: variant.id, subscribe: "true"})
      |> render_change()

      assert has_element?(view, "[data-testid=replaces-cart-note]", "Replaces the bouquet in your cart")
      assert has_element?(view, "[data-testid=add-to-cart-button]", "Update cart")
    end
  end

  test "an ordinary product offers no subscription", %{conn: conn} do
    product = generate(product(draft: false))
    generate(product_variant(product_id: product.id))

    {:ok, view, _html} = live(conn, ~p"/product/#{product.id}")

    refute has_element?(view, "[data-testid=product-subscribable]")
    refute has_element?(view, "[data-testid=subscribe-option]")
  end

  test "says why an add to the cart was refused", %{conn: conn, order: order} do
    product = generate(product(draft: false))
    variant = generate(product_variant(product_id: product.id))
    {:ok, view, _html} = live(conn, ~p"/product/#{product.id}")

    render_change(view, "change", %{product_variant_id: variant.id, subscribe: "true", interval_weeks: "2"})
    render_submit(view, "submit", %{})

    assert render(view) =~ "This product can&#39;t be subscribed to"
    assert line_items(order) == []
  end

  test "the store marks a subscribable product", %{conn: conn} do
    category = generate(product_category(slug: "bouquets", visibility: :public))
    product = generate(product(product_category_id: category.id, subscribable: true, free_delivery: true, draft: false))
    generate(product_variant(product_id: product.id, draft: false))

    {:ok, view, _html} = live(conn, ~p"/store/bouquets")

    assert has_element?(view, "#store-products", "Also as a subscription")
  end

  defp line_items(order) do
    Ash.read!(LineItem, authorize?: false) |> Enum.filter(&(&1.order_id == order.id))
  end
end
