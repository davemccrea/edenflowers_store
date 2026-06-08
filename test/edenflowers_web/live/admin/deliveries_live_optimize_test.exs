defmodule EdenflowersWeb.Admin.DeliveriesLiveOptimizeTest do
  # async: false — these drive the optimizer through the configured TourPlanning
  # implementation (the global :tour_planning config), which some cases override.
  use EdenflowersWeb.ConnCase, async: false

  import Generator
  import Phoenix.LiveViewTest

  alias AshAuthentication.Jwt
  alias AshAuthentication.Plug.Helpers

  defmodule UnassignedSolver do
    @behaviour Edenflowers.Geography.TourPlanning.Behaviour
    @impl true
    def solve(_problem), do: {:error, :unassigned}
  end

  defmodule FailingSolver do
    @behaviour Edenflowers.Geography.TourPlanning.Behaviour
    @impl true
    def solve(_problem), do: {:error, :tour_planning_failed}
  end

  defmodule StrategySolver do
    @behaviour Edenflowers.Geography.TourPlanning.Behaviour
    @impl true
    def solve(problem) do
      send(Application.fetch_env!(:edenflowers, :strategy_test_pid), {:strategy, problem.strategy})
      Edenflowers.Geography.TourPlanning.Fake.solve(problem)
    end
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

  # A successful optimize collapses the composer to bring the proposed routes forward,
  # so changing the selection or strategy again means expanding it first.
  defp expand_composer(view) do
    view |> element("button[phx-click=toggle_composer]") |> render_click()
  end

  test "starts with all orders selected and can exclude all", %{conn: conn} do
    first = eligible_order()
    second = eligible_order()
    generate(driver(name: "Dana"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")

    assert has_element?(view, "input#order-#{first.id}[checked]")
    assert has_element?(view, "input#order-#{second.id}[checked]")
    refute has_element?(view, "button[phx-click=optimize][disabled]")

    view |> element("#toggle-all-orders") |> render_click()

    refute has_element?(view, "input#order-#{first.id}[checked]")
    refute has_element?(view, "input#order-#{second.id}[checked]")
    refute has_element?(view, "#toggle-all-orders[checked]")
    assert has_element?(view, "button[phx-click=optimize][disabled]")

    view |> element("#toggle-all-orders") |> render_click()

    assert has_element?(view, "input#order-#{first.id}[checked]")
    assert has_element?(view, "input#order-#{second.id}[checked]")
    assert has_element?(view, "#toggle-all-orders[checked]")
  end

  test "optimizing renders the proposed routes via the fake", %{conn: conn} do
    eligible_order(order_reference: "EF-1", recipient_name: "Alice")
    eligible_order(order_reference: "EF-2", recipient_name: "Bob")
    generate(driver(name: "Dana"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")

    html = optimize(view)

    assert html =~ "Review routes"
    assert html =~ "Dana"
    assert html =~ "EF-1"
    assert html =~ "EF-2"
    assert html =~ "Alice"
    assert html =~ "4.0 km"
  end

  test "warns before navigating away from an optimized draft", %{conn: conn} do
    eligible_order()
    generate(driver(name: "Dana"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")

    assert has_element?(view, "#dispatch-draft-guard[data-active=false]")

    optimize(view)

    assert has_element?(
             view,
             "#dispatch-draft-guard[phx-hook=UnsavedChanges][data-active=true]"
           )
  end

  test "lets the florist choose how the run is optimized", %{conn: conn} do
    put_solver(StrategySolver)
    Application.put_env(:edenflowers, :strategy_test_pid, self())
    on_exit(fn -> Application.delete_env(:edenflowers, :strategy_test_pid) end)

    eligible_order()
    generate(driver(name: "Dana"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")

    assert has_element?(view, "#optimization-strategy input[value=cheapest][checked]")
    assert has_element?(view, "#optimization-strategy", "Balanced")
    assert has_element?(view, "#optimization-strategy", "Fastest")
    optimize(view)
    assert_receive {:strategy, :cheapest}

    expand_composer(view)

    view
    |> form("#optimization-strategy")
    |> render_change(%{"optimization" => %{"strategy" => "balanced"}})

    assert has_element?(view, "#optimization-strategy input[value=balanced][checked]")
    refute has_element?(view, "section", "Review routes")

    view |> element("button[phx-click=optimize]") |> render_click()
    render(view)
    assert_receive {:strategy, :balanced}

    expand_composer(view)

    view
    |> form("#optimization-strategy")
    |> render_change(%{"optimization" => %{"strategy" => "fastest"}})

    assert has_element?(view, "#optimization-strategy input[value=fastest][checked]")

    view |> element("button[phx-click=optimize]") |> render_click()
    render(view)
    assert_receive {:strategy, :fastest}
  end

  test "shows unused drivers the optimizer didn't route", %{conn: conn} do
    eligible_order()
    used = generate(driver(name: "Used Driver"))
    spare = generate(driver(name: "Spare Driver"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")
    view |> element("input#driver-#{used.id}") |> render_click()
    view |> element("input#driver-#{spare.id}") |> render_click()

    html = optimize(view)

    assert html =~ "Not used by the optimizer"
    assert html =~ "Spare Driver"
  end

  test "allows every proposed route to be assigned to the same driver", %{conn: conn} do
    eligible_order(order_reference: "EF-REASSIGN-1")
    eligible_order(order_reference: "EF-REASSIGN-2")
    first = generate(driver(name: "Driver A"))
    second = generate(driver(name: "Driver B"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")
    view |> element("input#driver-#{first.id}") |> render_click()
    view |> element("input#driver-#{second.id}") |> render_click()
    optimize(view)

    for draft_id <- ["0", "1"] do
      view
      |> form("#route-driver-form-#{draft_id}")
      |> render_change(%{
        "assignment" => %{"draft_id" => draft_id, "driver_id" => first.id}
      })

      assert has_element?(
               view,
               "#route-driver-#{draft_id} option[value='#{first.id}'][selected]"
             )
    end

    assert has_element?(view, "#proposed-route-0", "EF-REASSIGN")
    assert has_element?(view, "#proposed-route-1", "EF-REASSIGN")
  end

  test "changing the selection discards the draft", %{conn: conn} do
    order = eligible_order(order_reference: "EF-DRAFT")
    eligible_order(order_reference: "EF-OTHER")
    generate(driver(name: "Dana"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")
    assert optimize(view) =~ "Review routes"

    expand_composer(view)
    view |> element("input#order-#{order.id}") |> render_click()

    refute render(view) =~ "Review routes"
  end

  test "optimizing collapses the composer, and it can be reopened", %{conn: conn} do
    eligible_order()
    generate(driver(name: "Dana"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")
    assert has_element?(view, "#composer-body")

    optimize(view)
    refute has_element?(view, "#composer-body")

    expand_composer(view)
    assert has_element?(view, "#composer-body")
  end

  test "blocks with a message when an order can't be placed", %{conn: conn} do
    put_solver(UnassignedSolver)
    eligible_order()
    generate(driver(name: "Dana"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")

    html = optimize(view)

    assert html =~ "Some orders"
    assert html =~ "optimize again"
    refute html =~ "Review routes"
  end

  test "shows an error when the optimizer can't be reached", %{conn: conn} do
    put_solver(FailingSolver)
    eligible_order()
    generate(driver(name: "Dana"))

    {:ok, view, _html} = live(conn, ~p"/admin/deliveries/plan")

    html = optimize(view)

    assert html =~ "optimizer"
    assert html =~ "Try again"
  end

  defp with_token(user) do
    {:ok, token, _claims} = Jwt.token_for_user(user)
    %{user | __metadata__: Map.put(user.__metadata__ || %{}, :token, token)}
  end
end
