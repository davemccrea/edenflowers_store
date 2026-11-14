defmodule Edenflowers.Fulfillment.Actions.PlanRoute do
  @moduledoc """
  Orders a day's chosen deliveries into the fastest drive, with HERE. A route
  that can't be planned is a normal result, returned as `%{error: reason}`:
  `{:missed_windows, orders}` names the orders it can't reach in their agreed
  time.
  """
  use Ash.Resource.Actions.Implementation

  alias Edenflowers.External.HereAPI
  alias Edenflowers.Fulfillment
  alias Edenflowers.Orders
  alias Edenflowers.ShopTime

  @service_seconds 5 * 60

  # An order with a start time but no end is wanted at that time, give or take this.
  @single_time_slack_seconds 15 * 60

  @impl true
  def run(input, _opts, context) do
    %{order_ids: ids, date: date, start: start, finish: finish, departure: departure} = input.arguments

    with {:ok, orders} <- Orders.list_route_stops(ids, date, Ash.Context.to_opts(context)) do
      {:ok,
       plan(
         orders,
         Fulfillment.route_place_position(start),
         Fulfillment.route_place_position(finish),
         departure_at(date, departure)
       )}
    end
  end

  defp departure_at(date, time), do: DateTime.new!(date, time, ShopTime.timezone())

  defp plan([], _start, _finish, _departure), do: %{error: :no_stops}
  defp plan(_orders, nil, _finish, _departure), do: %{error: :no_home}
  defp plan(_orders, _start, nil, _departure), do: %{error: :no_home}

  defp plan(orders, start, finish, departure) do
    by_id = Map.new(orders, &{&1.id, &1})

    stops =
      Enum.map(orders, fn order ->
        %{id: order.id, position: order.position, service: @service_seconds, window: window(order)}
      end)

    case HereAPI.impl().sequence(start, stops, finish, departure) do
      {:ok, route} ->
        stops =
          Enum.map(route.stops, fn %{id: id, starts_at: starts_at} ->
            order = Map.fetch!(by_id, id)

            %{
              order: order,
              starts_at: DateTime.shift_zone!(starts_at, ShopTime.timezone()),
              window: window(order)
            }
          end)

        # HERE repeats windows weekly, so a window it can't make today it makes a week later.
        case Enum.filter(stops, &late?/1) do
          [] ->
            %{
              error: nil,
              start: start,
              finish: finish,
              stops: stops,
              back_at: DateTime.shift_zone!(route.back_at, ShopTime.timezone()),
              distance: route.distance,
              driving: route.driving
            }

          late ->
            %{error: {:missed_windows, Enum.map(late, & &1.order)}}
        end

      {:error, _reason} ->
        %{error: :route_not_planned}
    end
  end

  defp window(%{fulfillment_time_start: nil}), do: nil

  defp window(%{fulfillment_time_start: start, fulfillment_time_end: nil, fulfillment_date: date}) do
    at = departure_at(date, start)
    {DateTime.add(at, -@single_time_slack_seconds), DateTime.add(at, @single_time_slack_seconds)}
  end

  defp window(%{fulfillment_time_start: start, fulfillment_time_end: finish, fulfillment_date: date}),
    do: {departure_at(date, start), departure_at(date, finish)}

  defp late?(%{window: nil}), do: false
  defp late?(%{window: {_from, to}, starts_at: starts_at}), do: DateTime.after?(starts_at, to)
end
