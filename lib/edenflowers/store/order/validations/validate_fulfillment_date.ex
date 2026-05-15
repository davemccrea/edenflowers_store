defmodule Edenflowers.Store.Order.Validations.ValidateFulfillmentDate do
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Fulfillments
  alias Edenflowers.Store.FulfillmentOption

  @impl true
  def validate(changeset, _opts, _context) do
    fulfillment_date = Ash.Changeset.get_attribute(changeset, :fulfillment_date)
    option_id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)

    cond do
      is_nil(fulfillment_date) ->
        {:error, field: :fulfillment_date, message: "is required"}

      Date.compare(fulfillment_date, Date.utc_today()) == :lt ->
        {:error, field: :fulfillment_date, message: ~t"Fulfillment date cannot be in the past"}

      true ->
        check_availability(option_id, fulfillment_date)
    end
  end

  defp check_availability(nil, _date), do: :ok

  defp check_availability(option_id, date) do
    case FulfillmentOption.get_by_id(option_id, authorize?: false) do
      {:ok, option} ->
        case Fulfillments.fulfill_on_date(option, date) do
          {true, _} -> :ok
          {false, reason} -> {:error, field: :fulfillment_date, message: unavailable_message(reason)}
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
