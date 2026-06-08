defmodule Mix.Tasks.Eden.TourPlanningSpike do
  @moduledoc """
  Runs the real HERE Tour Planning adapter against today's seeded delivery orders and
  prints both the raw HERE response and the parsed per-driver routes.

  ## Why a Mix task

  The optimizer is the feature's principal risk: we need to confirm, against realistic
  Vaasa delivery sets, that each optimization strategy behaves as intended, and confirm
  HERE's live response field names before the adapter is relied on. This task is the HITL
  validation harness.

  ## Usage

      source .env
      mix eden.tour_planning_spike                       # 2 drivers, cheapest
      mix eden.tour_planning_spike 3                     # 3 drivers, cheapest
      mix eden.tour_planning_spike 3 balanced            # 3 drivers, balanced duration
      mix eden.tour_planning_spike 3 fastest             # 3 drivers, least total time

  Seed the database first (`mix ecto.setup` / seeds) so there are today-dated delivery
  orders to plan. Add more today deliveries to `priv/repo/seeds.exs` to exercise
  balancing across drivers.

  ## What to look at

  - **Raw response**: confirm the field names this adapter parses (`tours[].stops[]`,
    `distance`, `time.arrival`/`departure`, `activities[].jobId`, `unassigned`).
  - **Per-driver totals**: compare route counts, duration spread, and total distance
    across `cheapest`, `balanced`, and `fastest`.
  """
  use Mix.Task

  alias Edenflowers.Store.Order
  alias Edenflowers.Geography.TourPlanning.HERE

  require Ash.Query

  @shortdoc "Validate HERE Tour Planning against today's delivery orders"

  @impl Mix.Task
  def run(args) do
    Mix.Task.run("app.start")

    {driver_count, strategy} = parse_args(args)
    stops = todays_delivery_stops()

    if stops == [] do
      Mix.shell().error("No today-dated, paid, pending delivery orders with coordinates. Seed first.")
    else
      run_spike(stops, driver_count, strategy)
    end
  end

  defp run_spike(stops, driver_count, strategy) do
    drivers = for n <- 1..driver_count, do: %{id: "spike-#{n}"}
    problem = %{stops: stops, drivers: drivers, strategy: strategy}

    Mix.shell().info("Planning #{length(stops)} stops across #{driver_count} drivers using #{strategy}...\n")

    case HERE.post(HERE.build_problem(problem)) do
      {:ok, body} ->
        print_raw(body)
        print_parsed(HERE.parse_solution(body, problem))

      {:error, reason} ->
        Mix.shell().error("HERE request failed: #{inspect(reason)}")
    end
  end

  defp todays_delivery_stops do
    today = DateTime.now!("Europe/Helsinki") |> DateTime.to_date()
    handling = Application.get_env(:edenflowers, :delivery_handling_seconds, 300)

    Order
    |> Ash.Query.filter(
      state == :placed and payment_status == :paid and fulfillment_status == :pending and
        fulfillment_method == :delivery and fulfillment_date == ^today and not is_nil(position)
    )
    |> Ash.read!(actor: Edenflowers.Actors.system_actor(), authorize?: false)
    |> Enum.map(fn order ->
      %{id: order.id, position: order.position, handling_seconds: handling}
    end)
  end

  defp print_raw(body) do
    Mix.shell().info("=== RAW HERE RESPONSE ===")
    Mix.shell().info(Jason.encode!(body, pretty: true))
    Mix.shell().info("")
  end

  defp print_parsed({:error, :unassigned}) do
    Mix.shell().error("=== UNASSIGNED: HERE could not place every order (planning would be blocked) ===")
  end

  defp print_parsed({:error, reason}) do
    Mix.shell().error("=== PARSE ERROR: #{inspect(reason)} ===")
  end

  defp print_parsed({:ok, routes}) do
    Mix.shell().info("=== PARSED ROUTES ===")

    Enum.each(routes, fn route ->
      Mix.shell().info(
        "\nDriver #{route.driver_id}: #{length(route.stops)} stops | " <>
          "#{km(route.total_distance_m)} km | drive #{min(route.total_driving_s)} | " <>
          "total #{min(route.total_duration_s)}"
      )

      Enum.each(route.stops, fn stop ->
        leg = stop.leg_from_previous
        Mix.shell().info("  #{stop.sequence}. #{stop.stop_id}  (+#{km(leg.distance_m)} km, +#{min(leg.duration_s)})")
      end)
    end)

    total_km = routes |> Enum.map(& &1.total_distance_m) |> Enum.sum() |> km()
    total_time = routes |> Enum.map(& &1.total_duration_s) |> Enum.sum()

    Mix.shell().info(
      "\nDrivers used: #{length(routes)} | total driving: #{total_km} km | total delivery time: #{min(total_time)}"
    )
  end

  defp km(metres), do: Float.round(metres / 1000, 1)
  defp min(seconds), do: "#{div(seconds, 60)}m"

  defp parse_args([driver_count, "balanced" | _]),
    do: {String.to_integer(driver_count), :balanced}

  defp parse_args([driver_count, "fastest" | _]),
    do: {String.to_integer(driver_count), :fastest}

  defp parse_args([driver_count | _]), do: {String.to_integer(driver_count), :cheapest}
  defp parse_args(_), do: {2, :cheapest}
end
