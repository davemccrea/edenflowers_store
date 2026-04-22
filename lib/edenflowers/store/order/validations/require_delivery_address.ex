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

    delivery? =
      case FulfillmentOption.get_by_id(fulfillment_option_id, authorize?: false) do
        {:ok, %{fulfillment_method: :delivery}} -> true
        _ -> false
      end

    if delivery? and (is_nil(delivery_address) or String.trim(delivery_address) == "") do
      {:error, field: :delivery_address, message: ~t"Please enter and confirm a delivery address"}
    else
      :ok
    end
  end
end
