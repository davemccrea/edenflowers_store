defmodule EdenflowersWeb.Admin.CategoriesLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Generator

  alias Edenflowers.Catalog

  setup :log_in_admin

  test "the move buttons change the store order", %{conn: conn} do
    generate(product_category(name: "Bouquets", slug: "bouquets", position: 0, visibility: :public))
    plants = generate(product_category(name: "Plants", slug: "plants", position: 1, visibility: :public))

    {:ok, view, _html} = live(conn, ~p"/admin/products/categories")
    assert has_element?(view, "#category-#{plants.id} button[aria-label='Move Plants down'][disabled]")
    assert has_element?(view, "#category-#{plants.id} a[href='/admin/products?product_category.name=Plants']", "Plants")

    view |> element("button[aria-label='Move Plants up']") |> render_click()

    assert has_element?(view, "#categories li:first-child", "Plants")
    assert Enum.map(Catalog.list_categories!(), & &1.slug) == ["plants", "bouquets"]
  end

  test "choosing a visibility publishes a draft category", %{conn: conn} do
    christmas = generate(product_category(name: "Christmas", slug: "christmas", visibility: :draft))

    {:ok, view, _html} = live(conn, ~p"/admin/products/categories")
    assert has_element?(view, "#category-#{christmas.id} button[aria-pressed='true']", "Draft")

    view |> element("#category-#{christmas.id} button", "Public") |> render_click()

    assert has_element?(view, "#category-#{christmas.id} button[aria-pressed='true']", "Public")
    assert {:ok, _category} = Catalog.get_category_by_slug("christmas")
  end

  test "making a category with published products a draft asks first, naming how many leave the store", %{conn: conn} do
    bouquets = generate(product_category(name: "Bouquets", visibility: :public))
    empty = generate(product_category(name: "Plants", visibility: :public))
    generate(product(product_category_id: bouquets.id, draft: false))
    generate(product(product_category_id: bouquets.id, draft: false))
    generate(product(product_category_id: bouquets.id, draft: true))

    {:ok, view, _html} = live(conn, ~p"/admin/products/categories")

    assert view |> element("#category-#{bouquets.id} button", "Draft") |> render() =~
             "Make Bouquets a draft? Its 2 published products will leave the store and checkout."

    refute view |> element("#category-#{bouquets.id} button", "Hidden") |> render() =~ "data-confirm"
    refute view |> element("#category-#{empty.id} button", "Draft") |> render() =~ "data-confirm"
  end
end
