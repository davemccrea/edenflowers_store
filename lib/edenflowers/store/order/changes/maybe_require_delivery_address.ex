defmodule Edenflowers.Store.Order.MaybeRequireDeliveryAddress do
  @moduledoc """
  Conditionally requires a delivery address for delivery orders.

  If the selected fulfillment option has a fulfillment_method of :delivery,
  this change ensures that a delivery_address is provided. For pickup orders,
  the delivery address is optional.
  """
  use Ash.Resource.Change

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    fulfillment_option = Ash.Changeset.get_argument_or_attribute(changeset, :fulfillment_option)

    if not is_nil(fulfillment_option) and fulfillment_option.fulfillment_method == :delivery do
      Ash.Changeset.require_values(changeset, :update, false, [:delivery_address])
    else
      changeset
    end
  end
end
