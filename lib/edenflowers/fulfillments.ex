defmodule Edenflowers.Fulfillments do
  alias Edenflowers.Fulfillment.FulfillmentOption
  alias Edenflowers.Weekday
  import Decimal, only: [is_decimal: 1]

  defp here_api, do: Application.get_env(:edenflowers, :here_api, Edenflowers.HereAPI)

  use GettextSigils, backend: EdenflowersWeb.Gettext

  @type delivery_result :: %{
          geocoded_address: String.t(),
          position: String.t(),
          here_id: String.t(),
          distance: integer(),
          fulfillment_fee: Decimal.t()
        }

  @spec calculate_delivery(String.t(), FulfillmentOption.t()) ::
          {:ok, delivery_result()} | {:error, atom()}
  def calculate_delivery(delivery_address, fulfillment_option) do
    with {:ok, {geocoded_address, position, here_id}} <- here_api().get_address(delivery_address),
         {:ok, distance} <- here_api().get_distance(position),
         {:ok, fulfillment_fee} <- calculate_price(fulfillment_option, distance) do
      {:ok,
       %{
         geocoded_address: geocoded_address,
         position: position,
         here_id: here_id,
         distance: distance,
         fulfillment_fee: fulfillment_fee
       }}
    end
  end

  @doc """
  Single source of truth for user-facing delivery-related error messages.
  Used by the address input component (blur-time errors), the
  `CalculateFulfillmentCost` change (submit-time errors), and the
  `ValidateDeliveryAddress` validation (missing address).
  """
  @spec delivery_error_message(atom()) :: String.t()
  def delivery_error_message(:address_required), do: ~t"Delivery address required"
  def delivery_error_message(:address_not_found), do: ~t"Address not found"
  def delivery_error_message(:out_of_delivery_range), do: ~t"Outside delivery range"
  def delivery_error_message(_), do: ~t"There was a problem calculating delivery cost, please try again later"

  @spec calculate_price(FulfillmentOption.t(), number() | %Decimal{}) :: {:ok, %Decimal{}} | {:error, atom()}
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
        {:error, :out_of_delivery_range}
    end
  end

  @doc """
  Check if the order can be fulfilled on the given date.

  A date can be fulfilled except when:

    - The date is in the past
    - The date is disabled
    - The weekday is disabled and the date is not in the enabled dates
    - The date is today but the deadline for same day delivery has passed
    - The date is today but same day delivery is disabled
  """
  @spec fulfill_on_date(FulfillmentOption.t(), Date.t(), DateTime.t()) :: :ok | {:error, atom()}
  def fulfill_on_date(%FulfillmentOption{} = option, date, now \\ now()) do
    cond do
      date_past?(date, now) -> {:error, :past}
      date_disabled?(option, date) -> {:error, :date_disabled}
      not date_enabled?(option, date) and not weekday_enabled?(option, date) -> {:error, :weekday_disabled}
      (reason = today_blocked_reason(option, date, now)) != nil -> {:error, reason}
      true -> :ok
    end
  end

  @typedoc """
  Customer-facing calendar cell state. The customer can't act on the why-not,
  so every unavailable date — whether the weekday is off or the date is
  explicitly in `disabled_dates` — reads as `:closed`.
  """
  @type customer_cell_state :: :open | :closed | :past

  @typedoc """
  Admin-facing calendar cell state. The admin is editing the rules, so the
  distinction between `:weekday_disabled` (the weekday rule closes the date)
  and `:date_disabled` (an explicit override closes the date) matters —
  clicking each produces a different update.
  """
  @type admin_cell_state :: :open | :past | :weekday_disabled | :date_disabled

  @doc """
  Customer-facing cell state for the checkout calendar. `now` must be a
  `DateTime` because same-day deadline rules apply: today collapses to `:past`
  once the order deadline has passed or when `same_day: false`. From the
  customer's perspective, "can't pick today" looks identical to "the past".
  """
  @spec customer_cell_state(FulfillmentOption.t(), Date.t(), DateTime.t()) :: customer_cell_state()
  def customer_cell_state(fulfillment_option, date, now \\ now()) do
    case fulfill_on_date(fulfillment_option, date, now) do
      :ok -> :open
      {:error, :date_disabled} -> :closed
      {:error, :weekday_disabled} -> :closed
      {:error, _past_or_same_day} -> :past
    end
  end

  @doc """
  Admin-facing cell state for the date-toggle editor. `today` is a `Date`;
  same-day deadline rules are skipped because the admin is editing rules, not
  booking against them. Today reflects whatever the weekday rule and any
  per-date override say, so it can be toggled like any other date.
  """
  @spec admin_cell_state(FulfillmentOption.t(), Date.t(), Date.t()) :: admin_cell_state()
  def admin_cell_state(option, date, today) do
    cond do
      Date.compare(date, today) == :lt -> :past
      date in option.disabled_dates -> :date_disabled
      date in option.enabled_dates -> :open
      weekday_enabled?(option, date) -> :open
      true -> :weekday_disabled
    end
  end

  defp date_past?(date, now), do: Date.compare(date, now) == :lt

  defp date_disabled?(option, date), do: date in option.disabled_dates

  defp date_enabled?(option, date), do: date in option.enabled_dates

  defp weekday_enabled?(option, date), do: Weekday.from_date(date) in option.available_days

  defp today_blocked_reason(%{same_day: false}, date, now) do
    if date_today?(date, now), do: :same_day_delivery_disabled
  end

  defp today_blocked_reason(%{same_day: true, order_deadline: order_deadline}, date, now) do
    if date_today?(date, now) and Time.compare(now, order_deadline) == :gt do
      :order_deadline_passed
    end
  end

  defp date_today?(date, now), do: Date.compare(date, now) == :eq

  defp now(), do: DateTime.now!("Europe/Helsinki")
end
