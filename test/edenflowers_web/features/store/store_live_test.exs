defmodule EdenflowersWeb.Store.StoreLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  test "offers contact when the catalogue has no categories", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/en/store")

    assert has_element?(view, "h1", "Store")
    assert has_element?(view, "#store-products h2", "Nothing listed here just now")
    assert has_element?(view, "#store-products a[href='/en/contact']", "Get in touch")
    refute has_element?(view, "nav[aria-label='Categories']")
  end

  test "marks a product sold out once every size is", %{conn: conn} do
    category = generate(product_category(slug: "wreaths", visibility: :public))
    sold_out = generate(product(name: "Christmas wreath", product_category_id: category.id, draft: false))
    generate(product_variant(product_id: sold_out.id, size: :small, stock_quantity: 0))
    generate(product_variant(product_id: sold_out.id, size: :large, stock_quantity: 0))
    partly = generate(product(name: "Door wreath", product_category_id: category.id, draft: false))
    generate(product_variant(product_id: partly.id, size: :small, stock_quantity: 0))
    generate(product_variant(product_id: partly.id, size: :large, stock_quantity: 2))

    {:ok, view, _html} = live(conn, ~p"/en/store/wreaths")

    assert has_element?(view, "a[href='/en/product/#{sold_out.id}'] [data-testid=sold-out]")
    refute has_element?(view, "a[href='/en/product/#{partly.id}'] [data-testid=sold-out]")
  end

  test "/store opens on bouquets", %{conn: conn} do
    generate(product_category(slug: "bouquets", visibility: :public))

    assert {:error, {:live_redirect, %{to: "/en/store/bouquets"}}} = live(conn, ~p"/en/store")
  end

  test "an unknown category is a 404", %{conn: conn} do
    assert_error_sent 404, fn -> get(conn, ~p"/en/store/no-such-category") end
  end
end
