defmodule Edenflowers.Store.Order.Validations.ValidateFulfillmentDate do
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  @impl true
  def validate(changeset, _opts, _context) do
    fulfillment_date = Ash.Changeset.get_attribute(changeset, :fulfillment_date)

    cond do
      is_nil(fulfillment_date) ->
        {:error, field: :fulfillment_date, message: "is required"}

      Date.compare(fulfillment_date, Date.utc_today()) == :lt ->
        {:error, field: :fulfillment_date, message: ~t"Fulfillment date cannot be in the past"}

      true ->
        :ok
    end
  end
end
