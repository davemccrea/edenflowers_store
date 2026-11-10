defmodule EdenflowersWeb.Admin.ProductsLiveTest do
  # Query counts must not include broadcasts from concurrent tests.
  use EdenflowersWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Generator

  alias EdenflowersWeb.QueryCounter

  setup :log_in_admin

  test "notes and readiness changes do not query the product list", %{conn: conn, admin: admin} do
    order = placed_order(fulfillment_date: Edenflowers.ShopTime.today())
    {:ok, view, _html} = live(conn, ~p"/admin/products")
    render_async(view)
    reads = QueryCounter.track(view.pid)

    {:ok, order} = Edenflowers.Orders.update_florist_note(order, %{florist_note: "White flowers"}, actor: admin)
    render_async(view)
    assert QueryCounter.count(reads) == 0

    {:ok, order} = Edenflowers.Orders.mark_order_ready(order, actor: admin)
    render_async(view)
    assert QueryCounter.count(reads) == 0

    {:ok, _order} = Edenflowers.Orders.undo_order_ready(order, actor: admin)
    render_async(view)
    assert QueryCounter.count(reads) == 0
  end

  test "searches products by name", %{conn: conn} do
    generate(product(name: "Rose bouquet"))
    generate(product(name: "Tulip bouquet"))

    {:ok, view, _html} = live(conn, ~p"/admin/products?search=rose")
    html = render_async(view, 500)

    assert html =~ "Rose bouquet"
    refute html =~ "Tulip bouquet"
  end

  test "stock changes elsewhere preserve the category filter, price sort and current page", %{conn: conn, admin: admin} do
    category = generate(product_category(name: "Bouquets"))

    variants =
      for n <- 1..11 do
        product = generate(product(name: "Bouquet #{n}", product_category_id: category.id))
        generate(product_variant(product_id: product.id, price: n * 10, stock_quantity: 3))
      end

    hidden = generate(product(name: "Another category"))
    generate(product_variant(product_id: hidden.id, price: "200.00"))
    variant = List.last(variants)
    order = generate(order(state: :placed, fulfillment_date: Edenflowers.ShopTime.today(), payment_intent_id: nil))
    generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 2))

    {:ok, view, _html} =
      live(
        conn,
        ~p"/admin/products?#{%{"product_category.name" => "Bouquets", "sort" => "cheapest_price", "page_size" => 10, "page" => 2}}"
      )

    render_async(view)
    row = ~s([data-item-id="#{variant.product_id}"])
    assert has_element?(view, row, "3 left")
    assert has_element?(view, ~s([data-key="pagination_info_class"]), "showing 11-11 of 11")
    reads = QueryCounter.track(view.pid)

    {:ok, _cancelled} = Edenflowers.Orders.cancel_order(order, %{email_customer?: false}, actor: admin)
    Process.sleep(200)
    render_async(view)

    assert has_element?(view, row, "5 left")
    assert has_element?(view, ~s([data-key="pagination_info_class"]), "showing 11-11 of 11")
    refute has_element?(view, ~s([data-item-id="#{hd(variants).product_id}"]))
    refute has_element?(view, ~s([data-item-id="#{hidden.id}"]))
    assert QueryCounter.count(reads) > 0
  end

  test "lists drafts and flags products without sizes", %{conn: conn} do
    category = generate(product_category(name: "Bouquets"))
    sized = generate(product(name: "Rose bouquet", product_category_id: category.id, draft: false))
    generate(product_variant(product_id: sized.id, price: "40.00"))
    generate(product(name: "Tulip bouquet", product_category_id: category.id))

    {:ok, view, _html} = live(conn, ~p"/admin/products")
    html = render_async(view, 500)

    assert html =~ "Rose bouquet"
    assert html =~ "Bouquets"
    assert html =~ "Published"
    assert html =~ "Tulip bouquet"
    assert html =~ "Draft"
    assert html =~ "No sizes"
  end

  test "marks the products that can be bought as a subscription", %{conn: conn} do
    generate(product(name: "Rose bouquet"))

    {:ok, view, _html} = live(conn, ~p"/admin/products")
    refute render_async(view, 500) =~ "Can be bought as a subscription"

    generate(product(name: "Weekly bouquet", subscribable: true, free_delivery: true))

    {:ok, view, _html} = live(conn, ~p"/admin/products")
    assert render_async(view, 500) =~ "Can be bought as a subscription"
  end

  test "shows how many of each tracked size are left", %{conn: conn} do
    wreath = generate(product(name: "Christmas wreath"))
    generate(product_variant(product_id: wreath.id, size: :small, stock_quantity: 0))
    generate(product_variant(product_id: wreath.id, size: :large, stock_quantity: 3))
    generate(product_variant(product_id: wreath.id, size: :medium))

    {:ok, view, _html} = live(conn, ~p"/admin/products")
    html = render_async(view, 500)

    assert html =~ "Small: sold out"
    assert html =~ "Large: 3 left"
    refute html =~ "Medium:"
  end

  test "sorts by category and price", %{conn: conn} do
    anemones = generate(product_category(name: "Anemones"))
    zinnias = generate(product_category(name: "Zinnias"))
    cheap = generate(product(name: "Cheap one", product_category_id: zinnias.id))
    dear = generate(product(name: "Dear one", product_category_id: anemones.id))
    generate(product_variant(product_id: cheap.id, price: "10.00"))
    generate(product_variant(product_id: dear.id, price: "90.00"))

    {:ok, view, _html} = live(conn, ~p"/admin/products?sort=product_category.name")
    assert render_async(view, 500) =~ ~r/Dear one.*Cheap one/s

    {:ok, view, _html} = live(conn, ~p"/admin/products?sort=-cheapest_price")
    assert render_async(view, 500) =~ ~r/Dear one.*Cheap one/s

    {:ok, view, _html} = live(conn, ~p"/admin/products?sort=cheapest_price")
    assert render_async(view, 500) =~ ~r/Cheap one.*Dear one/s

    {:ok, view, _html} = live(conn, ~p"/admin/products?#{%{"product_category.name" => "Anemones"}}")
    html = render_async(view, 500)
    assert html =~ "Dear one"
    refute html =~ "Cheap one"
  end
end
