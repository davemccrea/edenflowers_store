defmodule Edenflowers.Fulfillment do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  alias Edenflowers.Expressions.HelsinkiToday

  def shop_address, do: "Muurahaistie 1, 65230 Vaasa"

  @doc "The delivery option priced by distance, whose free distance free-delivery products get."
  def distance_priced_delivery do
    Enum.find(list_options!(authorize?: false), &(&1.fulfillment_method == :delivery and &1.rate_type == :dynamic))
  end

  @doc "How far free-delivery products are delivered for free, or nil when nothing is."
  def free_dist_km do
    case distance_priced_delivery() do
      %{free_dist_km: km} when km > 0 -> km
      _ -> nil
    end
  end

  @doc """
  Whether customers can order for today with the options that offer same-day:
  `:open`, `:paused` when every one of them has today closed, or `:not_offered`.
  """
  def same_day_today(opts) do
    today = HelsinkiToday.today()

    case same_day_options(opts) do
      [] -> :not_offered
      options -> if Enum.all?(options, &(today in &1.disabled_dates)), do: :paused, else: :open
    end
  end

  @doc "Close or reopen today on every same-day option. Admins can still place orders for today."
  def set_same_day_today(:paused, opts),
    do: Enum.each(same_day_options(opts), &close_date!(&1, HelsinkiToday.today(), opts))

  def set_same_day_today(:open, opts),
    do: Enum.each(same_day_options(opts), &reopen_date!(&1, HelsinkiToday.today(), opts))

  defp same_day_options(opts), do: Enum.filter(list_options!(opts), & &1.same_day)

  resources do
    resource Edenflowers.Fulfillment.FulfillmentOption do
      define :list_options, action: :read
      define :list_options_for_checkout, action: :list_for_checkout
      define :get_option_by_id, action: :read, get_by: [:id]
      define :update_calendar, action: :update_calendar
      define :update_pricing, action: :update_pricing
      define :toggle_date, action: :toggle_date, args: [:date]
      define :set_weekday, action: :set_weekday, args: [:weekday, :direction]
      define :set_week, action: :set_week, args: [:week, :today, :direction]
      define :reset_calendar, action: :reset_calendar
      define :close_date, action: :close_date, args: [:date]
      define :reopen_date, action: :reopen_date, args: [:date]
      define :calculate_delivery, action: :calculate_delivery, args: [:delivery_address, :fulfillment_option_id]
      define :fulfill_on_date, action: :fulfill_on_date, args: [:fulfillment_option_id, :date]
    end
  end
end
