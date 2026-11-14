defmodule Edenflowers.Fulfillment do
  @moduledoc """
  Entry point for delivery, pickup, and shop availability.

  `FulfillmentOption` defines prices and delivery range. `ShopCalendar` defines
  the days Jennie works, shared by every option. `shop_address/0` and the
  distance-priced option helpers are used when quoting delivery.
  """

  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  def shop_address, do: "Muurahaistie 1, 65230 Vaasa"

  @doc "Where a delivery route can start or finish: the shop always, and Jennie's home when it's configured."
  def route_places, do: if(route_place_position(:home), do: [:shop, :home], else: [:shop])

  @doc "A route place's coordinates, \"latitude,longitude\", or nil when home isn't configured."
  def route_place_position(:shop), do: Edenflowers.External.HereAPI.shop_position()
  def route_place_position(:home), do: Application.get_env(:edenflowers, :home_position)

  @doc "Returns the distance-priced delivery option, or nil."
  def distance_priced_delivery do
    Enum.find(list_options!(authorize?: false), &(&1.fulfillment_method == :delivery and &1.rate_type == :dynamic))
  end

  @doc "Returns the free-delivery radius in kilometres, or nil when no positive radius is configured."
  def free_dist_km do
    case distance_priced_delivery() do
      %{free_dist_km: km} when km > 0 -> km
      _ -> nil
    end
  end

  resources do
    resource Edenflowers.Fulfillment.FulfillmentOption do
      define :list_options, action: :read
      define :list_options_for_checkout, action: :list_for_checkout
      define :get_option_by_id, action: :read, get_by: [:id]
      define :update_pricing, action: :update_pricing
      define :calculate_delivery, action: :calculate_delivery, args: [:delivery_address, :fulfillment_option_id]
      define :plan_route, action: :plan_route, args: [:order_ids, :date, :start, :finish, :departure]
    end

    resource Edenflowers.Fulfillment.ShopCalendar do
      define :get_shop_calendar, action: :get
      define :update_same_day, action: :update_same_day
      define :set_christmas_vouchers_online, action: :set_christmas_vouchers_online, args: [:christmas_vouchers_online]
      define :toggle_date, action: :toggle_date, args: [:date]
      define :set_weekday, action: :set_weekday, args: [:weekday, :direction]
      define :set_week, action: :set_week, args: [:week, :today, :direction]
      define :reset_calendar, action: :reset_calendar
    end
  end
end
