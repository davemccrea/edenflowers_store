defmodule Edenflowers.Orders.Order.Validations.ValidateDeliveryAddress do
  use Ash.Resource.Validation

  alias Edenflowers.Fulfillments

  @impl true
  def validate(changeset, _opts, _context) do
    method = Ash.Changeset.get_attribute(changeset, :fulfillment_method)
    delivery_address = Ash.Changeset.get_attribute(changeset, :delivery_address)

    if method == :delivery and blank?(delivery_address) do
      {:error, field: :delivery_address, message: Fulfillments.delivery_error_message(:address_required)}
    else
      :ok
    end
  end

  defp blank?(nil), do: true
  defp blank?(value) when is_binary(value), do: String.trim(value) == ""
end
