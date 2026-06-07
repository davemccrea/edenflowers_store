defmodule EdenflowersWeb.DriverRouteLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias Edenflowers.Delivery.Route
  alias Edenflowers.Store.Order

  defp today, do: DateTime.now!("Europe/Helsinki") |> DateTime.to_date()

  # Publishes a route for the driver with the given stop maps (sequence is inferred from order).
  defp publish_route(driver, stops, date \\ nil) do
    stops =
      stops
      |> Enum.with_index(1)
      |> Enum.map(fn {stop, sequence} ->
        Map.merge(
          %{
            sequence: sequence,
            order_id: generate(order()).id,
            order_reference: "EF-#{sequence}",
            leg_distance_m: 2_000,
            leg_duration_s: 300,
            products: []
          },
          stop
        )
      end)

    Route.publish!(%{date: date || today(), driver_id: driver.id, stops: stops}, authorize?: false)
  end

  test "renders the driver's name, the date, and their stops", %{conn: conn} do
    driver = generate(driver(name: "Dana"))

    publish_route(driver, [
      %{
        order_reference: "EF-100",
        recipient_name: "Alice",
        recipient_phone: "+358401112222",
        delivery_address: "Some Street 1",
        delivery_instructions: "Ring twice",
        card_message: "Happy Birthday",
        products: [%{"name" => "Roses", "quantity" => 2}],
        position: "63.0951,21.6165"
      }
    ])

    {:ok, _view, html} = live(conn, ~p"/d/#{driver.link_token}")

    assert html =~ "Dana"
    assert html =~ "Collect from shop"
    assert html =~ "EF-100"
    assert html =~ "Alice"
    assert html =~ "Some Street 1"
    assert html =~ "Ring twice"
    assert html =~ "Happy Birthday"
    assert html =~ "Roses"
    # Tap-to-call and a current-location directions link (origin omitted).
    assert html =~ ~s(href="tel:+358401112222")
    assert html =~ "https://www.google.com/maps/dir/?api=1&amp;destination=63.0951,21.6165"
  end

  test "offers a single Google Maps link chaining every stop in order", %{conn: conn} do
    driver = generate(driver(name: "Dana"))

    publish_route(driver, [
      %{order_reference: "EF-1", position: "63.01,21.01"},
      %{order_reference: "EF-2", position: "63.02,21.02"}
    ])

    publish_route(driver, [%{order_reference: "EF-3", position: "63.03,21.03"}])

    {:ok, _view, html} = live(conn, ~p"/d/#{driver.link_token}")

    # Last stop across all routes is the destination; the earlier ones are ordered waypoints.
    assert html =~ "Open all stops in Google Maps"

    assert html =~
             "https://www.google.com/maps/dir/?api=1&amp;travelmode=driving&amp;destination=63.03,21.03&amp;waypoints=63.01,21.01|63.02,21.02"
  end

  test "hides the all-stops link when no stop has a position", %{conn: conn} do
    driver = generate(driver(name: "Dana"))
    publish_route(driver, [%{order_reference: "EF-1", position: nil}])

    {:ok, _view, html} = live(conn, ~p"/d/#{driver.link_token}")

    refute html =~ "Open all stops in Google Maps"
  end

  test "renders every route for the day as its own list", %{conn: conn} do
    driver = generate(driver(name: "Dana"))
    publish_route(driver, [%{order_reference: "EF-RUN1"}])
    publish_route(driver, [%{order_reference: "EF-RUN2"}])

    {:ok, view, _html} = live(conn, ~p"/d/#{driver.link_token}")

    html = render(view)
    assert html =~ "EF-RUN1"
    assert html =~ "EF-RUN2"
    # One "Collect from shop" marker per route.
    assert html |> String.split("Collect from shop") |> length() == 3
  end

  test "renders in the driver's preferred locale", %{conn: conn} do
    driver = generate(driver(name: "Sven", locale: "sv-FI"))
    publish_route(driver, [%{order_reference: "EF-SV"}])

    {:ok, _view, html} = live(conn, ~p"/d/#{driver.link_token}")

    assert html =~ ~s(lang="sv-FI")
  end

  test "shows a clear empty state when the driver has nothing to deliver", %{conn: conn} do
    driver = generate(driver(name: "Idle"))

    {:ok, _view, html} = live(conn, ~p"/d/#{driver.link_token}")

    assert html =~ "Idle"
    assert html =~ "Nothing to deliver today."
    refute html =~ "Collect from shop"
  end

  test "an unknown token shows a not-found page", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/d/not-a-real-token")

    assert html =~ "isn&#39;t valid" or html =~ "isn't valid"
    refute html =~ "Collect from shop"
  end

  test "recording a delivery collapses the stop and fulfills the order", %{conn: conn} do
    driver = generate(driver(name: "Dana"))
    order = generate(order(fulfillment_status: :pending))
    publish_route(driver, [%{order_reference: "EF-1", order_id: order.id}])

    {:ok, view, _html} = live(conn, ~p"/d/#{driver.link_token}")

    view |> element(~s(button[phx-value-kind="delivered"])) |> render_click()
    html = view |> form("form", %{choice: "handed_to_recipient", note: ""}) |> render_submit()

    assert html =~ "Delivered"
    refute html =~ "Mark delivered"
    assert Order.get_by_id!(order.id, authorize?: false).fulfillment_status == :fulfilled
  end

  test "recording a failure shows the reason and leaves the order pending", %{conn: conn} do
    driver = generate(driver(name: "Dana"))
    order = generate(order(fulfillment_status: :pending))
    publish_route(driver, [%{order_reference: "EF-1", order_id: order.id}])

    {:ok, view, _html} = live(conn, ~p"/d/#{driver.link_token}")

    view |> element(~s(button[phx-value-kind="failed"])) |> render_click()
    html = view |> form("form", %{choice: "recipient_unavailable", note: ""}) |> render_submit()

    assert html =~ "Recipient unavailable"
    # The failed stop is still actionable for a retry.
    assert html =~ "Mark delivered"
    assert Order.get_by_id!(order.id, authorize?: false).fulfillment_status == :pending
  end

  test "choosing \"other\" without a note is rejected with a message", %{conn: conn} do
    driver = generate(driver(name: "Dana"))
    order = generate(order(fulfillment_status: :pending))
    publish_route(driver, [%{order_reference: "EF-1", order_id: order.id}])

    {:ok, view, _html} = live(conn, ~p"/d/#{driver.link_token}")

    view |> element(~s(button[phx-value-kind="delivered"])) |> render_click()
    html = view |> form("form", %{choice: "other", note: ""}) |> render_submit()

    assert html =~ "Please add a note"
    assert Order.get_by_id!(order.id, authorize?: false).fulfillment_status == :pending
  end
end
