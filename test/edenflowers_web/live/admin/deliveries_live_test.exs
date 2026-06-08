defmodule EdenflowersWeb.Admin.DeliveriesLiveTest do
  use EdenflowersWeb.ConnCase, async: true

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers

  setup %{conn: conn} do
    admin = generate(admin_user()) |> with_token()

    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Helpers.store_in_session(admin)

    %{conn: conn, admin: admin}
  end

  defp eligible_order(overrides \\ []) do
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

  test "shows the empty state when nothing is eligible today", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/deliveries/plan")
    assert html =~ "No deliveries are waiting to be assigned"
  end

  test "lists eligible orders pre-selected", %{conn: conn} do
    order = eligible_order(order_reference: "EF-100", recipient_name: "Recipient One")

    {:ok, view, html} = live(conn, ~p"/admin/deliveries/plan")

    assert html =~ "EF-100"
    assert html =~ "Recipient One"
    assert has_element?(view, "input#order-#{order.id}[checked]")
  end

  test "pre-selects the only active driver", %{conn: conn} do
    eligible_order()
    driver = generate(driver(name: "Solo Driver"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")

    assert has_element?(view, "input#driver-#{driver.id}[checked]")
  end

  test "does not pre-select drivers when several are active", %{conn: conn} do
    eligible_order()
    a = generate(driver(name: "Driver A"))
    b = generate(driver(name: "Driver B"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")

    refute has_element?(view, "input#driver-#{a.id}[checked]")
    refute has_element?(view, "input#driver-#{b.id}[checked]")
  end

  test "toggling an order excludes it", %{conn: conn} do
    order = eligible_order()

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")
    assert has_element?(view, "input#order-#{order.id}[checked]")

    view |> element("input#order-#{order.id}") |> render_click()

    refute has_element?(view, "input#order-#{order.id}[checked]")
  end

  test "toggling a driver selects it", %{conn: conn} do
    eligible_order()
    a = generate(driver(name: "Driver A"))
    _b = generate(driver(name: "Driver B"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")
    refute has_element?(view, "input#driver-#{a.id}[checked]")

    view |> element("input#driver-#{a.id}") |> render_click()

    assert has_element?(view, "input#driver-#{a.id}[checked]")
  end

  test "the build routes button is disabled when no orders are selected", %{conn: conn} do
    order = eligible_order()
    generate(driver(name: "Solo Driver"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")
    refute has_element?(view, "button[phx-click=optimize][disabled]")

    view |> element("input#order-#{order.id}") |> render_click()

    assert has_element?(view, "button[phx-click=optimize][disabled]")
  end

  test "the optimize button is disabled when no drivers are selected", %{conn: conn} do
    eligible_order()
    generate(driver(name: "Driver A"))
    generate(driver(name: "Driver B"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")

    assert has_element?(view, "button[phx-click=optimize][disabled]")
  end

  defp with_token(user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end
end
