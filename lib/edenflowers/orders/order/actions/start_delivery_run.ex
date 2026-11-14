defmodule Edenflowers.Orders.Order.Actions.StartDeliveryRun do
  @moduledoc """
  Numbers today's chosen deliveries as the stops of the day's Delivery run, in
  the order given, and takes any earlier stop the new run leaves out off it.
  Deliveries a route can't visit are skipped, as `route_stops` decides.
  """
  use Ash.Resource.Actions.Implementation

  require Ash.Query

  alias Edenflowers.Orders
  alias Edenflowers.Orders.Order

  @impl true
  def run(input, _opts, context) do
    %{date: date, order_ids: ids} = input.arguments
    opts = Ash.Context.to_opts(context)

    planned = %{
      at: Map.new(Enum.zip(ids, input.arguments[:planned_at] || [])),
      back_at: input.arguments[:planned_back_at]
    }

    if date == Edenflowers.ShopTime.today(),
      do: number_stops(date, ids, planned, opts),
      else:
        {:error, Ash.Error.Changes.InvalidArgument.exception(field: :date, message: "a Delivery run starts on its day")}
  end

  defp number_stops(date, ids, planned, opts) do
    with {:ok, stops} <- Orders.list_route_stops(ids, date, opts),
         {:ok, routed} <-
           Order |> Ash.Query.filter(fulfillment_date == ^date and not is_nil(route_position)) |> Ash.read(opts) do
      by_id = Map.new(stops, &{&1.id, &1})

      for order <- routed, not Map.has_key?(by_id, order.id), do: Orders.set_route_position!(order, nil, opts)

      ids
      |> Enum.flat_map(&List.wrap(by_id[&1]))
      |> Enum.with_index(1)
      |> Enum.each(fn {order, n} ->
        Orders.set_route_position!(
          order,
          n,
          %{route_planned_at: planned.at[order.id], route_planned_back_at: planned.back_at},
          opts
        )
      end)

      :ok
    end
  end
end
