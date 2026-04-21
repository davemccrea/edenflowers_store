defmodule Edenflowers.Store.Order.Validations.MaybeRequireDeliveryAddress do
  use Ash.Resource.Validation

  alias Edenflowers.Store.FulfillmentOption

  @impl true
  def validate(changeset, _opts, _context) do
    fulfillment_option_id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)
    delivery_address = Ash.Changeset.get_attribute(changeset, :delivery_address)

    is_delivery =
      case FulfillmentOption.get_by_id(fulfillment_option_id, authorize?: false) do
        {:ok, %{fulfillment_method: :delivery}} -> true
        _ -> false
      end

    if is_delivery and delivery_address in [nil, ""] do
      {:error, field: :delivery_address, message: "is required"}
    else
      :ok
    end
  end
end
