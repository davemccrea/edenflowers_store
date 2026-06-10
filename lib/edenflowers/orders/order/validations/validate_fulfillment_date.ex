defmodule Edenflowers.Orders.Order.Validations.ValidateFulfillmentDate do
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Fulfillment.FulfillmentOption

  @impl true
  def validate(changeset, _opts, _context) do
    fulfillment_date = Ash.Changeset.get_attribute(changeset, :fulfillment_date)
    option_id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)

    if is_nil(fulfillment_date) do
      {:error, field: :fulfillment_date, message: "is required"}
    else
      # All other rules (past, weekday, disabled_dates, same-day deadline) live
      # in the FulfillmentOption.fulfill_on_date action so the validator and the
      # calendar share one source of truth — including the Helsinki timezone.
      check_availability(option_id, fulfillment_date)
    end
  end

  defp check_availability(nil, _date), do: :ok

  defp check_availability(option_id, date) do
    case FulfillmentOption.fulfill_on_date(option_id, date, authorize?: false) do
      {:ok, %{error: nil}} -> :ok
      {:ok, %{error: reason}} -> {:error, field: :fulfillment_date, message: unavailable_message(reason)}
    end
  end

  defp unavailable_message(:past), do: ~t"Fulfillment date cannot be in the past"
  defp unavailable_message(:same_day_delivery_disabled), do: ~t"Same-day fulfillment is not available"
  defp unavailable_message(:order_deadline_passed), do: ~t"The order deadline for today has passed"
  defp unavailable_message(_), do: ~t"This date is no longer available, please choose another"
end
