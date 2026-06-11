defmodule Edenflowers.Orders.Order.Changes.CalculateFulfillmentCost do
  @moduledoc """
  For `submit_delivery`, derives `fulfillment_fee` (and, for delivery,
  the geocoded fields) from the chosen `FulfillmentOption`. The
  corresponding attributes are not in the action's `accept` list, so this
  change is the only path that can set them — closing the trust-the-client
  gap on delivery cost.
  """
  use Ash.Resource.Change

  alias Edenflowers.Fulfillment.DeliveryError
  alias Edenflowers.Fulfillment.FulfillmentOption

  @impl true
  def change(changeset, _opts, _context) do
    Ash.Changeset.before_action(changeset, &apply_cost/1)
  end

  defp apply_cost(changeset) do
    case Ash.Changeset.get_attribute(changeset, :fulfillment_method) do
      :pickup -> apply_pickup(changeset)
      :delivery -> apply_delivery(changeset)
      _ -> changeset
    end
  end

  defp apply_pickup(changeset) do
    id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)

    with {:ok, %{error: nil, fulfillment_fee: fee}} <-
           FulfillmentOption.calculate_price(id, 0, authorize?: false) do
      Ash.Changeset.force_change_attributes(changeset,
        fulfillment_fee: fee,
        delivery_address: nil,
        delivery_instructions: nil,
        geocoded_address: nil,
        position: nil,
        here_id: nil,
        distance: nil
      )
    else
      _ ->
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
          field: :fulfillment_option_id,
          message: DeliveryError.message(:unknown)
        })
    end
  end

  defp apply_delivery(changeset) do
    id = Ash.Changeset.get_attribute(changeset, :fulfillment_option_id)
    delivery_address = Ash.Changeset.get_attribute(changeset, :delivery_address)

    with {:ok, result} <- FulfillmentOption.calculate_delivery(delivery_address, id, authorize?: false) do
      if result.error do
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
          field: :delivery_address,
          message: DeliveryError.message(result.error)
        })
      else
        Ash.Changeset.force_change_attributes(changeset,
          geocoded_address: result.geocoded_address,
          position: result.position,
          here_id: result.here_id,
          distance: result.distance,
          fulfillment_fee: result.fulfillment_fee
        )
      end
    else
      _ ->
        Ash.Changeset.add_error(changeset, %Ash.Error.Changes.InvalidAttribute{
          field: :delivery_address,
          message: DeliveryError.message(:unknown)
        })
    end
  end
end
