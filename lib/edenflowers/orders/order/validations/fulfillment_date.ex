defmodule Edenflowers.Orders.Order.Validations.FulfillmentDate do
  @moduledoc """
  Checks a checkout date against the shop calendar, same-day rules, ordering
  deadline and the order's Available from.
  """

  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.Availability

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :fulfillment_date) do
      nil -> :ok
      date -> check_availability(changeset.data, date)
    end
  end

  defp check_availability(order, date) do
    calendar = Fulfillment.get_shop_calendar!(authorize?: false)
    available_from = Ash.load!(order, :available_from, authorize?: false, reuse_values?: false).available_from

    case Availability.unavailable_reason(calendar, date, Edenflowers.ShopTime.now(), available_from) do
      nil -> :ok
      reason -> {:error, field: :fulfillment_date, message: unavailable_message(reason, available_from)}
    end
  end

  defp unavailable_message(:past, _), do: ~t"Fulfillment date cannot be in the past"
  defp unavailable_message(:same_day_delivery_disabled, _), do: ~t"Same-day fulfillment is not available"
  defp unavailable_message(:order_deadline_passed, _), do: ~t"The order deadline for today has passed"

  defp unavailable_message(:before_available_from, available_from),
    do: Edenflowers.Format.available_from(available_from)

  defp unavailable_message(_, _), do: ~t"This date is no longer available, please choose another"
end
