defmodule Edenflowers.Orders.Order.Validations.ValidateFulfillmentDate do
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Fulfillments
  alias Edenflowers.Fulfillment.FulfillmentOption

  @impl true
  def validate(changeset, _opts, _context) do
    fulfillment_date = Ash.Changeset.get_attribute(changeset, :fulfillment_date)
    option_id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)

    if is_nil(fulfillment_date) do
      {:error, field: :fulfillment_date, message: "is required"}
    else
      # All other rules (past, weekday, disabled_dates, same-day deadline) live
      # in Fulfillments.fulfill_on_date/3 so the validator and the calendar
      # share one source of truth — including the Helsinki timezone used there.
      check_availability(option_id, fulfillment_date)
    end
  end

  defp check_availability(nil, _date), do: :ok

  defp check_availability(option_id, date) do
    case FulfillmentOption.get_by_id(option_id, authorize?: false) do
      {:ok, option} ->
        case Fulfillments.fulfill_on_date(option, date) do
          :ok -> :ok
          {:error, reason} -> {:error, field: :fulfillment_date, message: unavailable_message(reason)}
        end

      _ ->
        :ok
    end
  end

  defp unavailable_message(:past), do: ~t"Fulfillment date cannot be in the past"
  defp unavailable_message(:same_day_delivery_disabled), do: ~t"Same-day fulfillment is not available"
  defp unavailable_message(:order_deadline_passed), do: ~t"The order deadline for today has passed"
  defp unavailable_message(_), do: ~t"This date is no longer available, please choose another"
end
