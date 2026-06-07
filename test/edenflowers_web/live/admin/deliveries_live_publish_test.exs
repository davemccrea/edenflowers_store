defmodule EdenflowersWeb.Admin.DeliveriesLivePublishTest do
  # async: false — publishing opens a transaction that writes routes + stops across tables;
  # run serially to avoid lock contention with other tests creating orders concurrently.
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers
  alias Edenflowers.Delivery.RouteStop
  alias Edenflowers.Store.Order

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    %{conn: conn, admin: admin}
  end

  defp eligible_order(overrides) do
    today = DateTime.now!("Europe/Helsinki") |> DateTime.to_date()

    defaults = [
      state: :placed,
      payment_status: :paid,
      fulfillment_status: :pending,
      fulfillment_method: :delivery,
      fulfillment_date: today,
      position: "63.0951,21.6165",
      ordered_at: DateTime.utc_now()
    ]

    generate(order(Keyword.merge(defaults, overrides)))
  end

  defp optimize(view) do
    view |> element("button[phx-click=optimize]") |> render_click()
  end

  defp publish(view) do
    view |> element("button[phx-click=publish]") |> render_click()
    render(view)
  end

  test "publishing snapshots the order and removes it from eligibility", %{conn: conn} do
    product = generate(product(name: "Roses"))
    variant = generate(product_variant(product_id: product.id))
    card_product = generate(product(name: "Gift card"))
    card_variant = generate(product_variant(product_id: card_product.id))

    order =
      eligible_order(
        order_reference: "EF-PUB",
        recipient_name: "Alice",
        delivery_address: "Some Street 1",
        card_message: "Happy Birthday"
      )

    generate(line_item(order_id: order.id, product_variant_id: variant.id, quantity: 2))
    generate(line_item(order_id: order.id, product_variant_id: card_variant.id, is_card: true))

    generate(driver(name: "Dana"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries")
    optimize(view)
    html = publish(view)

    assert html =~ "Published routes"
    assert html =~ "Dana"
    assert html =~ "EF-PUB"
    assert html =~ "Alice"

    assert [stop] = Ash.read!(RouteStop, authorize?: false)
    assert stop.order_id == order.id
    assert stop.order_reference == "EF-PUB"
    assert stop.recipient_name == "Alice"
    assert stop.delivery_address == "Some Street 1"
    assert stop.card_message == "Happy Birthday"
    # The card line item is snapshotted as a message, not a product; prices are excluded.
    assert stop.products == [%{"name" => "Roses", "quantity" => 2}]
    assert stop.leg_distance_m == 2_000

    # The published order is no longer eligible, and its planning checkbox is gone.
    refute has_element?(view, "input#order-#{order.id}")
    today = DateTime.now!("Europe/Helsinki") |> DateTime.to_date()
    assert {:ok, []} = Order.list_eligible_for_delivery(%{date: today}, authorize?: false)
  end

  test "a second run plans only the orders left after the first is published", %{conn: conn} do
    first = eligible_order(order_reference: "EF-FIRST")
    second = eligible_order(order_reference: "EF-SECOND")
    generate(driver(name: "Dana"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries")

    # Publish only the first order.
    view |> element("input#order-#{second.id}") |> render_click()
    optimize(view)
    publish(view)

    # The second order remains eligible and selectable for another run.
    assert has_element?(view, "input#order-#{second.id}")
    refute has_element?(view, "input#order-#{first.id}")
  end

  defp with_token(user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end
end
