defmodule Edenflowers.Store.Order.MaybeRequireDeliveryAddress do
  @moduledoc """
  Conditionally requires a delivery address for delivery orders.

  If the selected fulfillment option has a fulfillment_method of :delivery,
  this change ensures that a delivery_address is provided. For pickup orders,
  the delivery address is optional.
  """
  use Ash.Resource.Change

  alias Edenflowers.Store.FulfillmentOption

  @impl true
  def init(opts), do: {:ok, opts}

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, fn changeset ->
      fulfillment_option_id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)

      if is_nil(fulfillment_option_id) do
        changeset
      else
        case FulfillmentOption.get_by_id(fulfillment_option_id, authorize?: false) do
          {:ok, %{fulfillment_method: :delivery}} ->
            Ash.Changeset.require_values(changeset, :update, false, [:delivery_address])

          _ ->
            changeset
        end
      end
    end)
  end
end
