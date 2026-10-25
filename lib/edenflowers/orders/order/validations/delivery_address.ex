defmodule Edenflowers.Orders.Order.Validations.DeliveryAddress do
  @moduledoc """
  Requires the delivery address fields needed to price and fulfill a delivery order.
  """

  use Ash.Resource.Validation

  alias Edenflowers.Fulfillment.DeliveryError

  @impl true
  def validate(changeset, _opts, _context) do
    method = Ash.Changeset.get_attribute(changeset, :fulfillment_method)
    delivery_address = Ash.Changeset.get_attribute(changeset, :delivery_address)

    if method == :delivery and is_nil(delivery_address) do
      {:error, field: :delivery_address, message: DeliveryError.message(:address_required)}
    else
      :ok
    end
  end
end
