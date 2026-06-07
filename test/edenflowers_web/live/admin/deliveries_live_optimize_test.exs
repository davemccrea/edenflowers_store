defmodule EdenflowersWeb.Admin.DeliveriesLiveOptimizeTest do
  # async: false — these drive the optimizer through the configured TourPlanning
  # implementation (the global :tour_planning config), which some cases override.
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers

  defmodule UnassignedSolver do
    @behaviour Edenflowers.TourPlanning.Behaviour
    @impl true
    def solve(_problem), do: {:error, :unassigned}
  end

  defmodule FailingSolver do
    @behaviour Edenflowers.TourPlanning.Behaviour
    @impl true
    def solve(_problem), do: {:error, :tour_planning_failed}
  end

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

  defp put_solver(implementation) do
    previous = Application.get_env(:edenflowers, :tour_planning)
    Application.put_env(:edenflowers, :tour_planning, implementation)
    on_exit(fn -> Application.put_env(:edenflowers, :tour_planning, previous) end)
  end

  defp optimize(view) do
    view |> element("button[phx-click=optimize]") |> render_click()
    render(view)
  end

  test "optimizing renders the proposed routes via the fake", %{conn: conn} do
    eligible_order(order_reference: "EF-1", recipient_name: "Alice")
    eligible_order(order_reference: "EF-2", recipient_name: "Bob")
    generate(driver(name: "Dana"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries")

    html = optimize(view)

    assert html =~ "Proposed routes"
    assert html =~ "Dana"
    assert html =~ "EF-1"
    assert html =~ "EF-2"
    assert html =~ "Alice"
    assert html =~ "4.0 km"
  end

  test "shows unused drivers the optimizer didn't route", %{conn: conn} do
    eligible_order()
    used = generate(driver(name: "Used Driver"))
    spare = generate(driver(name: "Spare Driver"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries")
    view |> element("input#driver-#{used.id}") |> render_click()
    view |> element("input#driver-#{spare.id}") |> render_click()

    html = optimize(view)

    assert html =~ "Not used by the optimizer"
    assert html =~ "Spare Driver"
  end

  test "changing the selection discards the draft", %{conn: conn} do
    order = eligible_order(order_reference: "EF-DRAFT")
    eligible_order(order_reference: "EF-OTHER")
    generate(driver(name: "Dana"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries")
    assert optimize(view) =~ "Proposed routes"

    view |> element("input#order-#{order.id}") |> render_click()

    refute render(view) =~ "Proposed routes"
  end

  test "blocks with a message when an order can't be placed", %{conn: conn} do
    put_solver(UnassignedSolver)
    eligible_order()
    generate(driver(name: "Dana"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries")

    html = optimize(view)

    assert html =~ "Some orders"
    assert html =~ "optimize again"
    refute html =~ "Proposed routes"
  end

  test "shows an error when the optimizer can't be reached", %{conn: conn} do
    put_solver(FailingSolver)
    eligible_order()
    generate(driver(name: "Dana"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries")

    html = optimize(view)

    assert html =~ "optimizer"
    assert html =~ "Try again"
  end

  defp with_token(user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end
end
