defmodule Edenflowers.Fulfillment do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

  def shop_address, do: "Muurahaistie 1, 65230 Vaasa"

  @doc "How far free-delivery products are delivered for free, or nil when nothing is."
  def free_dist_km do
    list_options!(authorize?: false)
    |> Enum.find(&(&1.fulfillment_method == :delivery and &1.rate_type == :dynamic))
    |> case do
      %{free_dist_km: km} when km > 0 -> km
      _ -> nil
    end
  end

  resources do
    resource Edenflowers.Fulfillment.FulfillmentOption do
      define :list_options, action: :read
      define :list_options_for_checkout, action: :list_for_checkout
      define :get_option_by_id, action: :read, get_by: [:id]
      define :update_calendar, action: :update_calendar
      define :toggle_date, action: :toggle_date, args: [:date]
      define :set_weekday, action: :set_weekday, args: [:weekday, :direction]
      define :set_week, action: :set_week, args: [:week, :today, :direction]
      define :reset_calendar, action: :reset_calendar

      define :calculate_delivery,
        action: :calculate_delivery,
        args: [:delivery_address, :fulfillment_option_id, {:optional, :free_delivery?}]

      define :fulfill_on_date, action: :fulfill_on_date, args: [:fulfillment_option_id, :date]
    end
  end
end
