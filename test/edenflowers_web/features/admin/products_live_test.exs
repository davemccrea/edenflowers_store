defmodule EdenflowersWeb.Admin.ProductsLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  alias AshAuthentication.Plug.Helpers

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()
    %{conn: conn |> Plug.Test.init_test_session(%{}) |> Helpers.store_in_session(admin)}
  end

  test "lists drafts and flags products without sizes", %{conn: conn} do
    category = generate(product_category(name: "Bouquets"))
    sized = generate(product(name: "Rose bouquet", product_category_id: category.id, draft: false))
    generate(product_variant(product_id: sized.id, price: "40.00"))
    generate(product(name: "Tulip bouquet", product_category_id: category.id))

    {:ok, view, _html} = live(conn, ~p"/admin/products")
    html = render_async(view)

    assert html =~ "Rose bouquet"
    assert html =~ "Bouquets"
    assert html =~ "Published"
    assert html =~ "Tulip bouquet"
    assert html =~ "Draft"
    assert html =~ "No sizes"
  end

  test "sorts by category and price", %{conn: conn} do
    anemones = generate(product_category(name: "Anemones"))
    zinnias = generate(product_category(name: "Zinnias"))
    cheap = generate(product(name: "Cheap one", product_category_id: zinnias.id))
    dear = generate(product(name: "Dear one", product_category_id: anemones.id))
    generate(product_variant(product_id: cheap.id, price: "10.00"))
    generate(product_variant(product_id: dear.id, price: "90.00"))

    {:ok, view, _html} = live(conn, ~p"/admin/products?sort=product_category.name")
    assert render_async(view) =~ ~r/Dear one.*Cheap one/s

    {:ok, view, _html} = live(conn, ~p"/admin/products?sort=-cheapest_price")
    assert render_async(view) =~ ~r/Dear one.*Cheap one/s

    {:ok, view, _html} = live(conn, ~p"/admin/products?sort=cheapest_price")
    assert render_async(view) =~ ~r/Cheap one.*Dear one/s

    {:ok, view, _html} = live(conn, ~p"/admin/products?#{%{"product_category.name" => "Anemones"}}")
    html = render_async(view)
    assert html =~ "Dear one"
    refute html =~ "Cheap one"
  end
end
