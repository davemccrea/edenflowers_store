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

    test "starts as a one-time purchase", %{conn: conn, product: product, order: order} do
      {:ok, view, _html} = live(conn, ~p"/product/#{product.id}")

      refute has_element?(view, "[data-testid=subscribe-option][checked]")
      assert has_element?(view, "[data-testid=subscription-faq] summary", "When do I pay?")
      refute has_element?(view, "[data-testid=interval-options]")
      refute has_element?(view, "[data-testid=per-delivery]")

      view |> form("[data-testid=product-form]") |> render_submit()

      assert [%LineItem{interval_weeks: nil}] = line_items(order)
    end

    test "can be subscribed to every few weeks", %{conn: conn, product: product, variant: variant, order: order} do
      {:ok, view, _html} = live(conn, ~p"/product/#{product.id}")
      view |> form("[data-testid=product-form]", %{subscribe: "true"}) |> render_change()

      assert has_element?(view, "[data-testid=interval-option-4]")
      assert has_element?(view, "[data-testid=subscription-explainer]", "charged 3 days before each one")
      assert has_element?(view, "[data-testid=per-delivery]", "per delivery")

      view
      |> form("[data-testid=product-form]", %{product_variant_id: variant.id, subscribe: "true", interval_weeks: "2"})
      |> render_change()

      assert render_submit(form(view, "[data-testid=product-form]"))
      assert_push_event(view, "js-exec", %{to: "#cart-drawer"})
      assert [%LineItem{interval_weeks: 2, quantity: 1}] = line_items(order)
    end

    test "starts from what's in the cart, and offers to update it", %{
      conn: conn,
      product: product,
      variant: variant,
      order: order
    } do
      Orders.add_line_item!(order.id, variant.id, 1, %{interval_weeks: 2}, authorize?: false)
      {:ok, view, _html} = live(conn, ~p"/product/#{product.id}")

      assert has_element?(view, "[data-testid=interval-option-2][checked]")
      assert has_element?(view, "[data-testid=add-to-cart-button]", "Show cart")

      view
      |> form("[data-testid=product-form]", %{product_variant_id: variant.id, subscribe: "false"})
      |> render_change()

      refute has_element?(view, "[data-testid=replaces-cart-note]")
      assert has_element?(view, "[data-testid=add-to-cart-button]", "Update cart")

      view |> form("[data-testid=product-form]") |> render_submit()

      assert [%LineItem{interval_weeks: nil}] = line_items(order)
    end

    test "counts the bouquets subscribing replaces", %{conn: conn, product: product, variant: variant, order: order} do
      Orders.add_line_item!(order.id, variant.id, 3, authorize?: false)
      {:ok, view, _html} = live(conn, ~p"/product/#{product.id}")

      view
      |> form("[data-testid=product-form]", %{product_variant_id: variant.id, subscribe: "true"})
      |> render_change()

      assert has_element?(view, "[data-testid=replaces-cart-note]", "Replaces the 3 bouquets")
    end

    test "tells a subscriber they already have one", %{conn: conn, product: product, variant: variant} do
      user = generate(admin_user(admin: false)) |> with_token()

      generate(subscription(user_id: user.id, product_variant_id: variant.id))

      conn = AshAuthentication.Plug.Helpers.store_in_session(conn, user)
      {:ok, view, _html} = live(conn, ~p"/product/#{product.id}")
      view |> form("[data-testid=product-form]", %{subscribe: "true"}) |> render_change()

      assert has_element?(view, ~s|[data-testid=already-subscribed] a[href="/account"]|)
    end

    test "says before the click that a subscription can't join other products", %{
      conn: conn,
      product: product,
      order: order
    } do
      other = generate(product(draft: false))
      other_variant = generate(product_variant(product_id: other.id))
      Orders.add_line_item!(order.id, other_variant.id, 1, authorize?: false)
      {:ok, view, _html} = live(conn, ~p"/product/#{product.id}")
      view |> form("[data-testid=product-form]", %{subscribe: "true"}) |> render_change()

      assert has_element?(view, "[data-testid=blocked-note]", "checked out on its own")
      refute has_element?(view, "[data-testid=add-to-cart-button][type=submit]")
    end
  end

  test "an ordinary product offers no subscription", %{conn: conn} do
    product = generate(product(draft: false))
    generate(product_variant(product_id: product.id))

    {:ok, view, _html} = live(conn, ~p"/product/#{product.id}")

    refute has_element?(view, "[data-testid=product-subscribable]")
    refute has_element?(view, "[data-testid=subscribe-option]")
    refute has_element?(view, "[data-testid=subscription-faq]")
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

    assert has_element?(view, "#store-products", "Subscription")
  end

  defp line_items(order) do
    Ash.read!(LineItem, authorize?: false) |> Enum.filter(&(&1.order_id == order.id))
  end
end
