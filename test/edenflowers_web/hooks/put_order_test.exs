defmodule EdenflowersWeb.Hooks.PutOrderTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  require Ash.Query

  test "a visit opens no cart before the first add to cart", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/about")

    assert has_element?(view, ~s|button[aria-label="Cart, empty"]|)
    refute Edenflowers.Orders.Order |> Ash.Query.filter(not is_nil(visitor_id)) |> Ash.exists?(authorize?: false)
  end

  test "mounts with the browser's cart", %{conn: conn} do
    order = generate(order())
    variant = generate(product_variant(product_id: generate(product()).id))
    generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 1))

    {:ok, view, _html} = conn |> with_cart(order) |> live(~p"/en/about")

    assert has_element?(view, ~s|button[aria-label="Cart, 1 item"]|)
  end

  test "a placed order is no longer the browser's cart", %{conn: conn} do
    order = generate(order())
    variant = generate(product_variant(product_id: generate(product()).id))
    generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 1))
    conn = with_cart(conn, order)
    Ash.Seed.update!(order, %{state: :placed})

    {:ok, view, _html} = live(conn, ~p"/en/about")

    assert has_element?(view, ~s|button[aria-label="Cart, empty"]|)
  end
end
