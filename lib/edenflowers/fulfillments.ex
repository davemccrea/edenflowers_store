defmodule Edenflowers.Fulfillments do
  alias Edenflowers.Store.FulfillmentOption
  import Decimal, only: [is_decimal: 1]

  use Gettext, backend: EdenflowersWeb.Gettext

  @spec calculate_price(FulfillmentOption.t(), number() | %Decimal{}) ::
          {:ok, %Decimal{}} | {:error, {atom(), binary()}}
  def calculate_price(fulfillment_option, distance \\ Decimal.new("0"))

  def calculate_price(%{rate_type: :fixed, base_price: base_price}, _distance) do
    {:ok, base_price}
  end

  def calculate_price(%{rate_type: :dynamic} = fulfillment_option, distance) when is_integer(distance) do
    calculate_price(fulfillment_option, Decimal.new(distance))
  end

  def calculate_price(%{rate_type: :dynamic} = fulfillment_option, distance) when is_decimal(distance) do
    %{
      price_per_km: price_per_km,
      base_price: base_price,
      free_dist_km: free_dist_km,
      max_dist_km: max_dist_km
    } =
      fulfillment_option

    price_per_m = Decimal.div(price_per_km, 1000)
    free_dist_m = Decimal.mult(free_dist_km, 1000)
    max_dist_m = Decimal.mult(max_dist_km, 1000)

    cond do
      Decimal.lte?(distance, free_dist_m) ->
        {:ok, Decimal.new("0")}

      Decimal.gt?(distance, free_dist_m) and Decimal.lt?(distance, max_dist_m) ->
        {:ok,
         distance
         |> Decimal.sub(free_dist_m)
         |> Decimal.mult(price_per_m)
         |> Decimal.add(base_price)
         |> Decimal.round(2)}

      true ->
        {:error, {:out_of_delivery_range, gettext("Out of delivery range")}}
    end
  end

  @doc """
  Check if the order can be fulfilled on the given date.

  A date can be fufilled except when:

    - The date is in the past
    - The date is disabled
    - The day of week is disabled and the date is not in the enabled dates
    - The date is today but the deadline for same day delivery has passed
    - The date is today but same day delivery is disabled
  """
  @spec fulfill_on_date(FulfillmentOption.t(), Date.t(), DateTime.t()) :: {boolean(), atom()}
  def fulfill_on_date(fulfillment_option = %FulfillmentOption{}, date, now \\ now()) do
    params = {fulfillment_option, date, now}

    case {date_past?(params), date_disabled?(params), date_enabled?(params), weekday_enabled?(params),
          fulfill_today?(params)} do
      {true, _, _, _, _} -> {false, :past}
      {_, true, _, _, _} -> {false, :date_disabled}
      {_, _, false, false, _} -> {false, :day_of_week_disabled}
      {_, _, _, _, {false, reason}} -> {false, reason}
      _ -> {true, :ok}
    end
  end

  defp date_past?({_, date, now}) do
    Date.compare(date, now) == :lt
  end

  defp date_disabled?({%{disabled_dates: disabled_dates}, date, _}) do
    Enum.member?(disabled_dates, date)
  end

  defp date_enabled?({%{enabled_dates: enabled_dates}, date, _}) do
    Enum.member?(enabled_dates, date)
  end

  defp weekday_enabled?({fulfillment_option, date, _now}) do
    day =
      date
      |> Date.day_of_week()
      |> day_of_week_to_atom()

    Map.get(fulfillment_option, day)
  end

  defp fulfill_today?({%{same_day: false, order_deadline: _order_deadline}, date, now}) do
    if date_today?(date, now) do
      {false, :same_day_delivery_disabled}
    end
  end

  defp fulfill_today?({%{same_day: true, order_deadline: order_deadline}, date, now}) do
    if date_today?(date, now) and Time.compare(now, order_deadline) == :gt do
      {false, :order_deadline_passed}
    end
  end

  defp date_today?(date, now), do: Date.compare(date, now) == :eq

  defp day_of_week_to_atom(n) do
    case n do
      1 -> :monday
      2 -> :tuesday
      3 -> :wednesday
      4 -> :thursday
      5 -> :friday
      6 -> :saturday
      7 -> :sunday
    end
  end

  defp now(), do: DateTime.now!("Europe/Helsinki")
end
