defmodule Edenflowers.Store.Order.Validations.RequireDeliveryAddress do
  use Ash.Resource.Validation
  use GettextSigils, backend: EdenflowersWeb.Gettext

  alias Edenflowers.Store.FulfillmentOption

  @impl true
  def validate(changeset, _opts, _context) do
    fulfillment_option_id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)
    # Argument carries the user's typed value during phx-change; falls back to
    # the persisted attribute (set by confirm_delivery_address).
    delivery_address =
      Ash.Changeset.get_argument(changeset, :delivery_address) ||
        Ash.Changeset.get_attribute(changeset, :delivery_address)

    if delivery?(changeset, fulfillment_option_id) and
         (is_nil(delivery_address) or String.trim(delivery_address) == "") do
      {:error, field: :delivery_address, message: ~t"Please enter and confirm a delivery address"}
    else
      :ok
    end
  end

  defp delivery?(changeset, fulfillment_option_id) do
    loaded = changeset.data.fulfillment_option

    option =
      cond do
        match?(%FulfillmentOption{}, loaded) and loaded.id == fulfillment_option_id ->
          loaded

        not is_nil(fulfillment_option_id) ->
          case FulfillmentOption.get_by_id(fulfillment_option_id, authorize?: false) do
            {:ok, opt} -> opt
            _ -> nil
          end

        true ->
          nil
      end

    match?(%FulfillmentOption{fulfillment_method: :delivery}, option)
  end
end
