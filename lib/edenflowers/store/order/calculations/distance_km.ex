defmodule Edenflowers.Store.Order.Calculations.DistanceKm do
  use Ash.Resource.Calculation

  @impl true
  def load(_query, _opts, _context), do: [:fulfillment_method, :distance]

  @impl true
  def calculate(records, _opts, _context) do
    Enum.map(records, fn
      %{fulfillment_method: :delivery, distance: distance} when is_integer(distance) ->
        format_distance_km(distance)

      _ ->
        nil
    end)
  end

  defp format_distance_km(distance) do
    distance
    |> Decimal.new()
    |> Decimal.div(1000)
    |> Decimal.round(1)
    |> Decimal.normalize()
    |> Decimal.to_string(:normal)
  end
end
