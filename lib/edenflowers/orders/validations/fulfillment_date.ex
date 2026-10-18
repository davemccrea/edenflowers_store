defmodule Edenflowers.Orders.Validations.FulfillmentDate do
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Fulfillment
  alias Edenflowers.Fulfillment.Availability

  @impl true
  def validate(changeset, _opts, _context) do
    case Ash.Changeset.get_attribute(changeset, :fulfillment_date) do
      nil -> :ok
      date -> check_availability(date)
    end
  end

  defp check_availability(date) do
    calendar = Fulfillment.get_shop_calendar!(authorize?: false)

    case Availability.unavailable_reason(calendar, date, Edenflowers.ShopTime.now()) do
      nil -> :ok
      reason -> {:error, field: :fulfillment_date, message: unavailable_message(reason)}
    end
  end

  defp unavailable_message(:past), do: ~t"Fulfillment date cannot be in the past"
  defp unavailable_message(:same_day_delivery_disabled), do: ~t"Same-day fulfillment is not available"
  defp unavailable_message(:order_deadline_passed), do: ~t"The order deadline for today has passed"
  defp unavailable_message(_), do: ~t"This date is no longer available, please choose another"
end
