defmodule Edenflowers.Fulfillment do
  use Ash.Domain,
    otp_app: :edenflowers,
    extensions: [AshAdmin.Domain]

  admin do
    show?(true)
  end

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
  Apply `:same_day` and/or `:order_deadline` to every option, or to none if any
  refuses them. Each option can still change them on its own afterwards.
  """
  def set_same_day_for_all(changes, opts) do
    Ash.bulk_update(
      Edenflowers.Fulfillment.FulfillmentOption,
      :update_pricing,
      changes,
      Keyword.merge(opts, return_records?: true, return_errors?: true)
    )
  end

  resources do
    resource Edenflowers.Fulfillment.FulfillmentOption do
      define :list_options, action: :read
      define :list_options_for_checkout, action: :list_for_checkout
      define :get_option_by_id, action: :read, get_by: [:id]
      define :update_pricing, action: :update_pricing
      define :toggle_date, action: :toggle_date, args: [:date]
      define :set_weekday, action: :set_weekday, args: [:weekday, :direction]
      define :set_week, action: :set_week, args: [:week, :today, :direction]
      define :reset_calendar, action: :reset_calendar
      define :calculate_delivery, action: :calculate_delivery, args: [:delivery_address, :fulfillment_option_id]
    end
  end
end
